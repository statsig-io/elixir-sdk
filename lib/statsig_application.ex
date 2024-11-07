defmodule Statsig.Application do
  use Application

  def start(_type, _args) do
    children = [
      {Statsig.Configs, []},
      {Statsig.Logging, []}
    ]

    opts = [strategy: :one_for_one, name: Statsig.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def stop(_state) do
    Logger.info("Stopping Statsig application")
    :ok
  end
end
