defmodule Statsig.Application do
  use Application
  require Logger

  def start(_type, _args) do
    Logger.error("Starting Statsig application")
    Logger.error("All running applications: #{inspect(Application.started_applications())}")
    Logger.error("Start type: #{inspect(_type)}")
    Logger.error("Process dictionary: #{inspect(Process.get())}")
    Logger.error("System flags: #{inspect(System.get_env())}")
    Logger.error("Full stacktrace:", %{
      stacktrace: try do
        throw(:trace)
      catch
        :trace -> __STACKTRACE__
      end
    })
    children = [
      {Statsig.Configs, []},
      {Statsig.Logging, []}
    ]

    opts = [strategy: :one_for_one, name: Statsig.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def stop(_state) do
    :ok
  end
end
