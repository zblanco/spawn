defmodule ActorsTest do
  use Actors.DataCase, async: false

  alias Eigr.Functions.Protocol.ActorInvocationResponse
  alias Eigr.Functions.Protocol.Actors.ActorState
  alias Eigr.Functions.Protocol.RegistrationResponse

  setup do
    actor_name = "global_actor_test"

    actor = build_actor(name: actor_name)
    actor_entry = build_actor_entry(name: actor_name, actor: actor)
    registry = build_registry_with_actors(actors: actor_entry)
    system = build_system(name: "spawn-system", registry: registry)

    request = build_registration_request(actor_system: system)
    {:ok, %RegistrationResponse{}} = Actors.register(request)

    %{system: system, actor: actor}
  end

  describe "register/1" do
    test "register actors for a system" do
      system = build_system_with_actors()
      request = build_registration_request(actor_system: system)

      assert {:ok, %RegistrationResponse{}} = Actors.register(request)
    end
  end

  describe "get_state/2" do
    test "get_state for a newly registered actor" do
      actor_name = "actor_test_" <> Ecto.UUID.generate()

      actor_entry = build_actor_entry(name: actor_name)
      registry = build_registry_with_actors(actors: actor_entry)
      system = build_system(registry: registry)

      request = build_registration_request(actor_system: system)

      {:ok, %RegistrationResponse{}} = Actors.register(request)

      {:ok, %ActorState{state: %Google.Protobuf.Any{value: state}}} =
        Actors.get_state(system.name, actor_name)

      assert %Actors.Protos.StateTest{name: "example_state_name_" <> _rand} =
               Actors.Protos.StateTest.decode(state)
    end
  end

  describe "invoke/2" do
    test "invoke actor function for a newly registered actor" do
      actor_name = "newly_actor_test_" <> Ecto.UUID.generate()

      actor = build_actor(name: actor_name)
      actor_entry = build_actor_entry(name: actor_name, actor: actor)
      registry = build_registry_with_actors(actors: actor_entry)
      system = build_system(registry: registry)

      request = build_registration_request(actor_system: system)

      {:ok, %RegistrationResponse{}} = Actors.register(request)

      # invoke
      invoke_request = build_invocation_request(system: system, actor: actor)

      host_invoke_response =
        build_host_invoke_response(actor_name: actor_name, system_name: system.name)

      mock_invoke_host_actor_with_ok_response(host_invoke_response)

      assert {:ok, %ActorInvocationResponse{actor_name: ^actor_name}} =
               Actors.invoke(invoke_request)
    end

    test "invoke actor function for a already registered actor in another node", ctx do
      %{system: system, actor: actor} = ctx
      actor_name = actor.id.name

      invoke_request = build_invocation_request(system: system, actor: actor)

      host_invoke_response =
        build_host_invoke_response(actor_name: actor_name, system_name: system.name)

      mock_invoke_host_actor_with_ok_response(host_invoke_response)

      assert {:ok, %ActorInvocationResponse{actor_name: ^actor_name}} =
               Actors.invoke(invoke_request)

      state =
        Actors.Protos.ChangeNameResponseTest.new(
          status: :NAME_ALREADY_TAKEN,
          new_name: "new_name"
        )
        |> any_pack!

      host_invoke_response =
        build_host_invoke_response(actor_name: actor_name, system_name: system.name, state: state)

      mock_invoke_host_actor_with_ok_response(host_invoke_response)

      assert {:ok,
              %ActorInvocationResponse{actor_name: ^actor_name, updated_context: updated_context}} =
               loop_until_ok(fn ->
                 Spawn.NodeHelper.rpc(:"spawn_actors_node@127.0.0.1", Actors, :invoke, [
                   invoke_request
                 ])
               end)

      assert %Actors.Protos.ChangeNameResponseTest{status: :NAME_ALREADY_TAKEN} =
               any_unpack!(updated_context.state, Actors.Protos.ChangeNameResponseTest)
    end

    test "invoke function for a new actor without persistence in another node", _ctx do
      actor_name = "actor_not_persistent"

      actor = build_actor(name: actor_name, persistent: false)
      actor_entry = build_actor_entry(name: actor_name, actor: actor)
      registry = build_registry_with_actors(actors: actor_entry)
      system = build_system(name: "spawn-system", registry: registry)

      request = build_registration_request(actor_system: system)
      {:ok, %RegistrationResponse{}} = Actors.register(request)

      invoke_request = build_invocation_request(system: system, actor: actor)

      state =
        Actors.Protos.ChangeNameResponseTest.new(
          status: :OK,
          new_name: "new_name"
        )
        |> any_pack!

      host_invoke_response =
        build_host_invoke_response(actor_name: actor_name, system_name: system.name, state: state)

      mock_invoke_host_actor_with_ok_response(host_invoke_response)

      assert {:ok,
              %ActorInvocationResponse{actor_name: ^actor_name, updated_context: updated_context}} =
               loop_until_ok(fn ->
                 Spawn.NodeHelper.rpc(:"spawn_actors_node@127.0.0.1", Actors, :invoke, [
                   invoke_request
                 ])
               end)

      assert %Actors.Protos.ChangeNameResponseTest{status: :OK} =
               any_unpack!(updated_context.state, Actors.Protos.ChangeNameResponseTest)
    end

    test "invoke async actor function", ctx do
      %{system: system, actor: actor} = ctx
      actor_name = actor.id.name

      invoke_request = build_invocation_request(system: system, actor: actor, async: true)

      host_invoke_response =
        build_host_invoke_response(actor_name: actor_name, system_name: system.name)

      mock_invoke_host_actor_with_ok_response(host_invoke_response)

      assert {:ok, :async} = Actors.invoke(invoke_request)
    end

    # Useful for distributed testing due to natural eventuality problems
    defp loop_until_ok(func, timeout \\ 10_000) do
      task = Task.async(fn -> do_loop(func, func.()) end)

      Task.await(task, timeout)
    end

    defp do_loop(_func, {:ok, term}), do: {:ok, term}

    defp do_loop(func, _resp) do
      do_loop(func, func.())
    rescue
      _ -> do_loop(func, func.())
    catch
      _ -> do_loop(func, func.())
    end
  end
end
