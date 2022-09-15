defmodule Actors do
  @moduledoc """
  Documentation for `Spawn`.
  """
  require Logger

  alias Actors.Actor.Entity, as: ActorEntity
  alias Actors.Actor.Entity.Supervisor, as: ActorEntitySupervisor

  alias Actors.Registry.ActorRegistry

  alias Eigr.Functions.Protocol.Actors.{Actor, ActorSystem, Registry}

  alias Eigr.Functions.Protocol.{
    InvocationRequest,
    ProxyInfo,
    RegistrationRequest,
    RegistrationResponse,
    ServiceInfo
  }

  @activate_actors_min_demand 0
  @activate_actors_max_demand 4

  @erpc_timeout 5_000

  def register(
        %RegistrationRequest{
          service_info: %ServiceInfo{} = _service_info,
          actor_system:
            %ActorSystem{name: _name, registry: %Registry{actors: actors} = _registry} =
              actor_system
        } = _registration
      ) do
    ActorRegistry.register(actors)

    with :ok <- create_actors(actor_system, actors) do
      proxy_info =
        ProxyInfo.new(
          protocol_major_version: 1,
          protocol_minor_version: 2,
          proxy_name: "spawn",
          proxy_version: "0.1.0"
        )

      # Start Activators here

      # Then response to the caller
      {:ok, RegistrationResponse.new(proxy_info: proxy_info)}
    end
  end

  def get_state(system_name, actor_name) do
    do_lookup_action(system_name, actor_name, nil, fn actor_ref ->
      ActorEntity.get_state(actor_ref)
    end)
  end

  def invoke(
        %InvocationRequest{
          actor: %Actor{} = actor,
          system: %ActorSystem{} = system,
          async: async?
        } = request
      ) do
    do_lookup_action(system.name, actor.name, system, fn actor_ref ->
      maybe_invoke_async(async?, actor_ref, request)
    end)
  end

  defp do_lookup_action(system_name, actor_name, system, action_fun) do
    case Spawn.Cluster.Node.Registry.lookup(Actors.Actor.Entity, actor_name) do
      [{actor_ref, nil}] ->
        Logger.debug("Lookup Actor #{actor_name}. PID: #{inspect(actor_ref)}")

        action_fun.(actor_ref)

      _ ->
        with {:ok, %{node: node, actor: actor}} <-
               ActorRegistry.lookup(system_name, actor_name),
             {:ok, actor_ref} <-
               :erpc.call(node, __MODULE__, :try_reactivate_actor, [system, actor], @erpc_timeout) do
          action_fun.(actor_ref)
        else
          {:not_found, _} ->
            Logger.error("Actor #{actor_name} not found on ActorSystem #{system_name}")
            {:error, "Actor #{actor_name} not found on ActorSystem #{system_name}"}

          {:erpc, :timeout} ->
            Logger.error(
              "Failed to invoke Actor #{actor_name} on ActorSystem #{system_name}: Node connection timeout"
            )

            {:error, "Node connection timeout"}

          {:error, reason} ->
            Logger.error(
              "Failed to invoke Actor #{actor_name} on ActorSystem #{system_name}: #{inspect(reason)}"
            )

            {:error, reason}

          _ ->
            Logger.error("Failed to invoke Actor #{actor_name} on ActorSystem #{system_name}")
            {:error, "Failed to invoke Actor #{actor_name} on ActorSystem #{system_name}"}
        end
    end
  end

  @spec maybe_invoke_async(boolean, term(), term()) :: :ok | {:ok, term()}
  defp maybe_invoke_async(true, actor_ref, request) do
    ActorEntity.invoke_async(actor_ref, request)
  end

  defp maybe_invoke_async(false, actor_ref, request) do
    ActorEntity.invoke(actor_ref, request)
  end

  def try_reactivate_actor(%ActorSystem{} = system, %Actor{name: name} = actor) do
    case ActorEntitySupervisor.lookup_or_create_actor(system, actor) do
      {:ok, actor_ref} ->
        Logger.debug("Actor #{name} reactivated. ActorRef PID: #{inspect(actor_ref)}")
        {:ok, actor_ref}

      reason ->
        Logger.error("Failed to reactivate actor #{name}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # To lookup all actors
  def try_reactivate_actor(nil, %Actor{name: name} = actor) do
    case ActorEntitySupervisor.lookup_or_create_actor(nil, actor) do
      {:ok, actor_ref} ->
        Logger.debug("Actor #{name} reactivated. ActorRef PID: #{inspect(actor_ref)}")
        {:ok, actor_ref}

      reason ->
        Logger.error("Failed to reactivate actor #{name}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp create_actors(actor_system, actors) do
    actors
    |> Flow.from_enumerable(
      min_demand: @activate_actors_min_demand,
      max_demand: @activate_actors_max_demand
    )
    |> Flow.map(fn {actor_name, actor} ->
      Logger.debug("Registering #{actor_name} #{inspect(actor)} on Node: #{inspect(Node.self())}")

      {time, result} = :timer.tc(&lookup_actor/3, [actor_system, actor_name, actor])

      Logger.info(
        "Registered and Activated the #{actor_name} on Node #{inspect(Node.self())} in #{inspect(time)}ms"
      )

      result
    end)
    |> Flow.run()
  end

  defp lookup_actor(actor_system, actor_name, actor) do
    case ActorEntitySupervisor.lookup_or_create_actor(actor_system, actor) do
      {:ok, pid} ->
        {:ok, pid}

      error ->
        Logger.debug("Failed to register Actor #{actor_name}")
        {:error, error}
    end
  end
end
