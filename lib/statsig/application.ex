defmodule Statsig.Application do
  use Application
  require Logger

  def start(_type, args) do
    api_key = Keyword.get(args, :api_key)
    Application.put_env(:statsig, :api_key, api_key)
    Logger.error("setting api key #{inspect(api_key)}")

    children = [
      Statsig.Configs,
      Statsig.Logging,
    ]

    opts = [strategy: :one_for_one, name: Statsig.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def stop(_state) do
    Logger.error("Statsig application stopping: #{inspect(Process.info(self()))}")
    :ok
  end
end
