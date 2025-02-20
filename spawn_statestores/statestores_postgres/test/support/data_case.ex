defmodule Statestores.DataCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  using do
    quote do
      use Statestores.SandboxHelper, repos: [Statestores.Util.load_adapter()]

      import Statestores.DataCase
    end
  end
end
