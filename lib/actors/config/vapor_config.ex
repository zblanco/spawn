defmodule Actors.Config.Vapor do
  @moduledoc """
  `Config.Vapor` Implements the `Config` behavior
  to allow the retrieval of system variables
  that will be included in the system configuration.
  """
  require Logger
  alias Vapor.Provider.{Env, Dotenv}

  @behaviour Actors.Config

  @default_actor_system_name "spawn-system"

  @impl true
  def load(mod) do
    case Agent.start_link(fn -> %{} end, name: mod) do
      {:ok, _pid} ->
        Agent.get_and_update(mod, fn state ->
          update_state(state)
        end)

      {:error, {:already_started, _pid}} ->
        Agent.get(mod, fn state -> state end)
    end
  end

  @impl true
  def get(mod, key), do: Agent.get(mod, fn state -> Map.get(state, key) end)

  defp load_system_env() do
    providers = [
      %Dotenv{},
      %Env{
        bindings: [
          {:app_name, "PROXY_APP_NAME", default: Config.Name.generate(), required: false},
          {:actor_system_name, "PROXY_ACTOR_SYSTEM_NAME",
           default: @default_actor_system_name, required: false},
          {:http_port, "PROXY_HTTP_PORT",
           default: 9001, map: &String.to_integer/1, required: false},
          {:proxy_http_client_adapter, "PROXY_HTTP_CLIENT_ADAPTER",
           default: "finch", required: false},
          {:deployment_mode, "PROXY_DEPLOYMENT_MODE", default: "sidecar", required: false},
          {:node_host_interface, "NODE_IP", default: "0.0.0.0", required: false},
          {:proxy_cluster_strategy, "PROXY_CLUSTER_STRATEGY", default: "gossip", required: false},
          {:proxy_headless_service, "PROXY_HEADLESS_SERVICE",
           default: "proxy-headless", required: false},
          {:proxy_cluster_polling_interval, "PROXY_CLUSTER_POLLING",
           default: 3_000, map: &String.to_integer/1, required: false},
          {:proxy_cluster_gossip_broadcast_only, "PROXY_CLUSTER_GOSSIP_BROADCAST_ONLY",
           default: "true", required: false},
          {:proxy_cluster_gossip_reuseaddr_address, "PROXY_CLUSTER_GOSSIP_REUSE_ADDRESS",
           default: "true", required: false},
          {:proxy_cluster_gossip_multicast_address, "PROXY_CLUSTER_GOSSIP_MULTICAST_ADDRESS",
           default: "255.255.255.255", required: false},
          {:proxy_uds_enable, "PROXY_UDS_ENABLED", default: false, required: false},
          {:proxy_sock_addr, "PROXY_UDS_ADDRESS",
           default: "/var/run/spawn.sock", required: false},
          {:proxy_host_interface, "POD_IP", default: "0.0.0.0", required: false},
          {:proxy_disable_metrics, "SPAWN_DISABLE_METRICS", default: "false", required: false},
          {:proxy_console_metrics, "SPAWN_CONSOLE_METRICS", default: "false", required: false},
          {:user_function_host, "USER_FUNCTION_HOST", default: "0.0.0.0", required: false},
          {:user_function_port, "USER_FUNCTION_PORT",
           default: 8090, map: &String.to_integer/1, required: false},
          # Internal Nats Protocol
          {:use_internal_nats, "SPAWN_USE_INTERNAL_NATS", default: "false", required: false},
          {:internal_nats_hosts, "SPAWN_INTERNAL_NATS_HOSTS",
           default: "nats://127.0.0.1:4222", required: false},
          {:internal_nats_tls, "SPAWN_INTERNAL_NATS_TLS", default: "false", required: false},
          {:internal_nats_auth, "SPAWN_INTERNAL_NATS_AUTH", default: "false", required: false},
          {:internal_nats_auth_type, "SPAWN_INTERNAL_NATS_AUTH_TYPE",
           default: "simple", required: false},
          {:internal_nats_auth_user, "SPAWN_INTERNAL_NATS_AUTH_USER",
           default: "admin", required: false},
          {:internal_nats_auth_pass, "SPAWN_INTERNAL_NATS_AUTH_PASS",
           default: "admin", required: false},
          {:internal_nats_auth_jwt, "SPAWN_INTERNAL_NATS_AUTH_JWT", default: "", required: false},

          # PubSub
          {:pubsub_adapter, "SPAWN_PUBSUB_ADAPTER", default: "native", required: false},
          {:pubsub_adapter_nats_hosts, "SPAWN_PUBSUB_NATS_HOSTS",
           default: "nats://127.0.0.1:4222", required: false},
          {:pubsub_adapter_nats_tls, "SPAWN_PUBSUB_NATS_TLS", default: "false", required: false},
          {:pubsub_adapter_nats_auth, "SPAWN_PUBSUB_NATS_AUTH",
           default: "false", required: false},
          {:pubsub_adapter_nats_auth_type, "SPAWN_PUBSUB_NATS_AUTH_TYPE",
           default: "simple", required: false},
          {:pubsub_adapter_nats_auth_user, "SPAWN_PUBSUB_NATS_AUTH_USER",
           default: "admin", required: false},
          {:pubsub_adapter_nats_auth_pass, "SPAWN_PUBSUB_NATS_AUTH_PASS",
           default: "admin", required: false},
          {:pubsub_adapter_nats_auth_jwt, "SPAWN_PUBSUB_NATS_AUTH_JWT",
           default: "", required: false},
          #
          {:delayed_invokes, "SPAWN_DELAYED_INVOKES", default: "true", required: false},
          {:sync_interval, "SPAWN_CRDT_SYNC_INTERVAL",
           default: 2, map: &String.to_integer/1, required: false},
          {:ship_interval, "SPAWN_CRDT_SHIP_INTERVAL",
           default: 2, map: &String.to_integer/1, required: false},
          {:ship_debounce, "SPAWN_CRDT_SHIP_DEBOUNCE",
           default: 2, map: &String.to_integer/1, required: false},
          {:neighbours_sync_interval, "SPAWN_STATE_HANDOFF_SYNC_INTERVAL",
           default: 60, map: &String.to_integer/1, required: false}
        ]
      }
    ]

    config = Vapor.load!(providers)

    Logger.info("Loading configs")

    Enum.each(config, fn {key, value} ->
      value_str = if String.contains?(Atom.to_string(key), "secret"), do: "****", else: value
      Logger.info("Loading config: [#{key}]:[#{value_str}]")
      Application.put_env(:spawn, key, value, persistent: true)
    end)

    set_http_client_adapter(config)

    config
  end

  defp set_http_client_adapter(config) do
    case config.proxy_http_client_adapter do
      _finch_only_now ->
        Application.put_env(:tesla, :adapter, {Tesla.Adapter.Finch, [name: SpawnHTTPClient]},
          persistent: true
        )
    end
  end

  defp update_state(state) do
    if state == %{} do
      config = load_system_env()
      {config, config}
    else
      {state, state}
    end
  end
end
