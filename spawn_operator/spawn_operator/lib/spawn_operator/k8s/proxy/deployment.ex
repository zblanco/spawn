defmodule SpawnOperator.K8s.Proxy.Deployment do
  @moduledoc false

  require Logger

  @behaviour SpawnOperator.K8s.Manifest

  @default_actor_host_function_env [
    %{
      "name" => "RELEASE_NAME",
      "value" => "spawn"
    },
    %{
      "name" => "NAMESPACE",
      "valueFrom" => %{"fieldRef" => %{"fieldPath" => "metadata.namespace"}}
    },
    %{
      "name" => "POD_IP",
      "valueFrom" => %{"fieldRef" => %{"fieldPath" => "status.podIP"}}
    },
    %{
      "name" => "SPAWN_PROXY_PORT",
      "value" => "9001"
    },
    %{
      "name" => "SPAWN_PROXY_INTERFACE",
      "value" => "0.0.0.0"
    },
    %{
      "name" => "RELEASE_DISTRIBUTION",
      "value" => "name"
    },
    %{
      "name" => "RELEASE_NODE",
      "value" => "$(RELEASE_NAME)@$(POD_IP)"
    }
  ]

  @default_actor_host_function_replicas 1

  @default_actor_host_resources %{
    "requests" => %{
      "cpu" => "100m",
      "memory" => "80Mi",
      "ephemeral-storage" => "1M"
    }
  }

  @default_proxy_resources %{
    "requests" => %{
      "cpu" => "50m",
      "memory" => "80Mi",
      "ephemeral-storage" => "1M"
    }
  }

  @default_termination_period_seconds 140

  @impl true
  def manifest(resource, _opts \\ []), do: gen_deployment(resource)

  defp gen_deployment(
         %{
           system: system,
           namespace: ns,
           name: name,
           params: params,
           labels: _labels,
           annotations: annotations
         } = _resource
       ) do
    host_params = Map.get(params, "host")
    replicas = max(1, Map.get(params, "replicas", @default_actor_host_function_replicas))
    embedded = Map.get(host_params, "embedded", false)

    maybe_warn_wrong_volumes(params, host_params)

    %{
      "apiVersion" => "apps/v1",
      "kind" => "Deployment",
      "metadata" => %{
        "name" => name,
        "namespace" => ns,
        "labels" => %{"app" => name, "actor-system" => system}
      },
      "spec" => %{
        "replicas" => replicas,
        "selector" => %{
          "matchLabels" => %{"app" => name, "actor-system" => system}
        },
        "strategy" => %{
          "type" => "RollingUpdate",
          "rollingUpdate" => %{
            "maxSurge" => 0,
            "maxUnavailable" => "20%"
          }
        },
        "template" => %{
          "metadata" => %{
            "annotations" => %{
              "prometheus.io/port" => "#{annotations.proxy_http_port}",
              "prometheus.io/path" => "/metrics",
              "prometheus.io/scrape" => "true"
            },
            "labels" => %{
              "app" => name,
              "actor-system" => system
            }
          },
          "spec" =>
            %{
              "affinity" => Map.get(host_params, "antiAffinity", build_anti_affinity(name)),
              "containers" => get_containers(embedded, system, name, host_params, annotations)
            }
            |> maybe_put_volumes(params)
            |> maybe_set_termination_period(params)
        }
      }
    }
  end

  defp build_anti_affinity(app_name) do
    %{
      "podAntiAffinity" => %{
        "preferredDuringSchedulingIgnoredDuringExecution" => [
          %{
            "podAffinityTerm" => %{
              "labelSelector" => %{
                "matchExpressions" => [
                  %{
                    "key" => "app",
                    "operator" => "In",
                    "values" => [
                      app_name
                    ]
                  }
                ]
              },
              "topologyKey" => "kubernetes.io/hostname"
            },
            "weight" => 100
          }
        ]
      }
    }
  end

  defp get_containers(true, system, name, host_params, annotations) do
    actor_host_function_image = Map.get(host_params, "image")

    actor_host_function_envs = Map.get(host_params, "env", []) ++ @default_actor_host_function_env

    proxy_http_port = String.to_integer(annotations.proxy_http_port)

    proxy_actor_host_function_ports = [
      %{"containerPort" => 4369, "name" => "epmd"},
      %{"containerPort" => proxy_http_port, "name" => "proxy-http"}
    ]

    actor_host_function_ports = Map.get(host_params, "ports", [])
    actor_host_function_ports = actor_host_function_ports ++ proxy_actor_host_function_ports

    actor_host_function_resources =
      Map.get(host_params, "resources", @default_actor_host_resources)

    host_and_proxy_container =
      %{
        "name" => "actor-host-function",
        "image" => actor_host_function_image,
        "env" => actor_host_function_envs,
        "envFrom" => [
          %{
            "configMapRef" => %{
              "name" => "#{name}-sidecar-cm"
            }
          },
          %{
            "secretRef" => %{
              "name" => "#{system}-secret"
            }
          }
        ],
        "ports" => actor_host_function_ports,
        "resources" => actor_host_function_resources
      }
      |> maybe_put_volume_mounts_to_host_container(host_params)

    [
      host_and_proxy_container
    ]
  end

  defp get_containers(false, system, name, host_params, annotations) do
    actor_host_function_image = Map.get(host_params, "image")

    actor_host_function_envs =
      Map.get(host_params, "env", []) ++
        @default_actor_host_function_env

    actor_host_function_resources =
      Map.get(host_params, "resources", @default_actor_host_resources)

    proxy_http_port = String.to_integer(annotations.proxy_http_port)

    proxy_actor_host_function_ports = [
      %{"containerPort" => 4369, "name" => "epmd"},
      %{"containerPort" => proxy_http_port, "name" => "proxy-http"}
    ]

    proxy_container = %{
      "name" => "spawn-sidecar",
      "image" => "#{annotations.proxy_image_tag}",
      "env" => @default_actor_host_function_env,
      "ports" => proxy_actor_host_function_ports,
      "livenessProbe" => %{
        "failureThreshold" => 10,
        "httpGet" => %{
          "path" => "/health/liveness",
          "port" => proxy_http_port,
          "scheme" => "HTTP"
        },
        "initialDelaySeconds" => 5,
        "periodSeconds" => 60,
        "successThreshold" => 1,
        "timeoutSeconds" => 30
      },
      "readinessProbe" => %{
        "httpGet" => %{
          "path" => "/health/readiness",
          "port" => proxy_http_port,
          "scheme" => "HTTP"
        },
        "initialDelaySeconds" => 5,
        "periodSeconds" => 5,
        "successThreshold" => 1,
        "timeoutSeconds" => 5
      },
      "resources" => @default_proxy_resources,
      "envFrom" => [
        %{
          "configMapRef" => %{
            "name" => "#{name}-sidecar-cm"
          }
        },
        %{
          "secretRef" => %{
            "name" => "#{system}-secret"
          }
        }
      ]
    }

    host_container =
      %{
        "name" => "actor-host-function",
        "image" => actor_host_function_image,
        "env" => actor_host_function_envs,
        "resources" => actor_host_function_resources
      }
      |> maybe_put_ports_to_host_container(host_params)
      |> maybe_put_volume_mounts_to_host_container(host_params)

    [
      proxy_container,
      host_container
    ]
  end

  defp maybe_put_ports_to_host_container(spec, %{"ports" => ports}) do
    Map.put(spec, "ports", ports)
  end

  defp maybe_put_ports_to_host_container(spec, _), do: spec

  defp maybe_set_termination_period(spec, %{
         "terminationGracePeriodSeconds" => terminationGracePeriodSeconds
       }) do
    Map.put(
      spec,
      "terminationGracePeriodSeconds",
      terminationGracePeriodSeconds || @default_termination_period_seconds
    )
  end

  defp maybe_set_termination_period(spec, _) do
    Map.put(spec, "terminationGracePeriodSeconds", @default_termination_period_seconds)
  end

  defp maybe_put_volumes(spec, %{"volumes" => volumes}) do
    Map.put(spec, "volumes", volumes)
  end

  defp maybe_put_volumes(spec, _), do: spec

  defp maybe_put_volume_mounts_to_host_container(spec, %{"volumeMounts" => volumeMounts}) do
    Map.put(spec, "volumeMounts", volumeMounts)
  end

  defp maybe_put_volume_mounts_to_host_container(spec, _), do: spec

  defp maybe_warn_wrong_volumes(params, host_params) do
    volumes = Map.get(params, "volumes", [])

    host_params
    |> Map.get("volumeMounts", [])
    |> Enum.each(fn mount ->
      if !Enum.find(volumes, &(&1["name"] == mount["name"])) do
        Logger.warn("Not found volume registered for #{mount["name"]}")
      end
    end)
  end
end
