defmodule StatsigEx.APIClient do
  def download_config_specs(api_key, since \\ 0) do
    {:ok, resp} =
      HTTPoison.get(
        "https://statsigapi.net/v1/download_config_specs?sinceTime=#{since}",
        [{"STATSIG-API-KEY", api_key}, {"Content-Type", "application/json"}]
      )

    Jason.decode(resp.body)
  end

  def push_logs(api_key, logs) do
    {:ok, resp} =
      HTTPoison.post(
        "https://statsigapi.net/v1/rgstr",
        Jason.encode!(%{"events" => logs}),
        [{"STATSIG-API-KEY", api_key}, {"Content-Type", "application/json"}]
      )

    Jason.decode(resp.body)
  end
end
