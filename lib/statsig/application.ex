defmodule Statsig.Application do
  use Application
  require Logger

  def start(_type, args) do
    children = [
      Statsig.Configs,
      Statsig.Logging
    ]

    opts = [strategy: :one_for_one, name: Statsig.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def stop(_state) do
    Logger.error("Statsig application stopping: #{inspect(Process.info(self()))}")
    :ok
  end
end
