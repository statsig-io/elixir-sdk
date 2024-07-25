defmodule StatsigEx.APIClient do
  def download_config_specs(api_key, since \\ 0) do
    # let it crash if it can't pull the specs. This will prevent startup, but that's probably a good thing
    {:ok, resp} =
      HTTPoison.get(
        "https://statsigapi.net/v1/download_config_specs?sinceTime=#{since}",
        [{"STATSIG-API-KEY", api_key}, {"Content-Type", "application/json"}]
      )

    Jason.decode(resp.body)
  end

  def push_logs(api_key, logs) do
    HTTPoison.post(
      "https://statsigapi.net/v1/rgstr",
      Jason.encode!(%{"events" => logs}),
      [{"STATSIG-API-KEY", api_key}, {"Content-Type", "application/json"}]
    )
    |> case do
      {:ok, %{status_code: code}} when code < 300 -> {:ok, []}
      _ -> {:error, logs}
    end
  end
end
