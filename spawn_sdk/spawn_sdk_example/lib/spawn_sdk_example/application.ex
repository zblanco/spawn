defmodule SpawnSdkExample.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {
        SpawnSdk.System.Supervisor,
        system: "spawn-system-1",
        actors: [
          SpawnSdkExample.Actors.JoeActor,
          SpawnSdkExample.Actors.JsonActor,
          # SpawnSdkExample.Actors.ClockActor,
          SpawnSdkExample.Actors.AbstractActor,
          SpawnSdkExample.Actors.PooledActor
        ],
        extenal_subscribers: [
          {SpawnSdkExample.Subscriber, []}
        ]
      }
    ]

    opts = [strategy: :one_for_one, name: SpawnSdkExample.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
