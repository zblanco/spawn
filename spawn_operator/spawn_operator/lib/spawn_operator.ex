defmodule SpawnOperator do
  @moduledoc """
  Documentation for `SpawnOperator`.
  """
  require Logger

  @actorsystem_apiversion_key "spawn-eigr.io/actor-system"
  @actorsystem_default_name "spawn-system"

  def get_args(resource) do
    _metadata = K8s.Resource.metadata(resource)
    labels = K8s.Resource.labels(resource)
    resource_annotations = K8s.Resource.annotations(resource)
    annotations = get_annotations_or_defaults(resource_annotations)

    ns = K8s.Resource.namespace(resource) || "default"
    name = K8s.Resource.name(resource)
    system = annotations.actor_system

    spec = Map.get(resource, "spec")

    %{
      system: system,
      namespace: ns,
      name: name,
      params: spec,
      labels: labels,
      annotations: annotations
    }
  end

  def get_annotations_or_defaults(annotations) do
    %{
      actor_system: Map.get(annotations, @actorsystem_apiversion_key, @actorsystem_default_name),
      user_function_host: Map.get(annotations, "spawn-eigr.io/app-host", "0.0.0.0"),
      user_function_port: Map.get(annotations, "spawn-eigr.io/app-port", "8090"),
      cluster_poling_interval:
        Map.get(annotations, "spawn-eigr.io/cluster-poling-interval", "3000"),
      proxy_mode: Map.get(annotations, "spawn-eigr.io/sidecar-mode", "sidecar"),
      proxy_http_port: Map.get(annotations, "spawn-eigr.io/sidecar-http-port", "9001"),
      proxy_image_tag:
        Map.get(
          annotations,
          "spawn-eigr.io/sidecar-image-tag",
          "docker.io/eigr/spawn-proxy:0.6.3"
        ),
      proxy_uds_enabled: Map.get(annotations, "spawn-eigr.io/sidecar-uds-enabled", "false"),
      proxy_uds_address:
        Map.get(annotations, "spawn-eigr.io/sidecar-uds-socket-path", "/var/run/spawn.sock"),
      metrics_port: Map.get(annotations, "spawn-eigr.io/sidecar-metrics-port", "9090"),
      metrics_disabled: Map.get(annotations, "spawn-eigr.io/sidecar-metrics-disabled", "false"),
      metrics_log_console:
        Map.get(annotations, "spawn-eigr.io/sidecar-metrics-log-console", "true"),
      pubsub_adapter: Map.get(annotations, "spawn-eigr.io/sidecar-pubsub-adapter", "native"),
      pubsub_nats_hosts:
        Map.get(annotations, "spawn-eigr.io/sidecar-pubsub-nats-hosts", "nats://127.0.0.1:4222"),
      pubsub_nats_tls: Map.get(annotations, "spawn-eigr.io/sidecar-pubsub-nats-tls", "false"),
      pubsub_nats_auth_type:
        Map.get(annotations, "spawn-eigr.io/sidecar-pubsub-nats-auth-type", "simple"),
      pubsub_nats_auth: Map.get(annotations, "spawn-eigr.io/sidecar-pubsub-nats-auth", "false"),
      pubsub_nats_auth_jwt:
        Map.get(annotations, "spawn-eigr.io/sidecar-pubsub-nats-auth-jwt", ""),
      pubsub_nats_auth_user:
        Map.get(annotations, "spawn-eigr.io/sidecar-pubsub-nats-auth-user", "admin"),
      pubsub_nats_auth_pass:
        Map.get(annotations, "spawn-eigr.io/sidecar-pubsub-nats-auth-pass", "admin"),
      delayed_invokes: Map.get(annotations, "spawn-eigr.io/sidecar-delayed-invokes", "true"),
      sync_interval: Map.get(annotations, "spawn-eigr.io/sidecar-crdt-sync-interval", "2"),
      ship_interval: Map.get(annotations, "spawn-eigr.io/sidecar-crdt-ship-interval", "2"),
      ship_debounce: Map.get(annotations, "spawn-eigr.io/sidecar-crdt-ship-debounce", "2"),
      neighbours_sync_interval:
        Map.get(annotations, "spawn-eigr.io/sidecar-state-handoff-sync-interval", "60")
    }
  end
end
