defmodule Statestores.Adapters.CockroachDB do
  @moduledoc """
  Implements the behavior defined in `Statestores.Adapters.Behaviour` for CockroachDB databases.
  """
  use Statestores.Adapters.Behaviour

  use Ecto.Repo,
    otp_app: :spawn_statestores,
    adapter: Ecto.Adapters.Postgres

  alias Statestores.Schemas.{Event, ValueObjectSchema}

  def get_by_key(id), do: get_by(Event, id: id)

  def save(
        %Event{
          system: system,
          actor: actor,
          revision: revision,
          tags: tags,
          data_type: type,
          data: data
        } = event
      ) do
    %Event{}
    |> Event.changeset(ValueObjectSchema.to_map(event))
    |> insert_or_update(
      on_conflict: [
        set: [
          system: system,
          actor: actor,
          revision: revision,
          tags: tags,
          data_type: type,
          data: data,
          updated_at: DateTime.utc_now()
        ]
      ],
      conflict_target: :actor
    )
    |> case do
      {:ok, event} ->
        {:ok, event}

      {:error, changeset} ->
        {:error, changeset}

      other ->
        {:error, other}
    end
  end

  def default_port, do: "26257"
end
