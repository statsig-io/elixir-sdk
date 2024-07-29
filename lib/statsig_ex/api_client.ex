defmodule StatsigEx.APIClient do
  def download_config_specs(api_key, since \\ 0) do
    # don't crash here, let the calling process decide
    with {:ok, resp} <-
           HTTPoison.get(
             "https://statsigapi.net/v1/download_config_specs?sinceTime=#{since}",
             headers(api_key)
           ) do
      Jason.decode(resp.body)
    else
      result -> result
    end
  end

  def push_logs(api_key, logs) do
    HTTPoison.post(
      "https://statsigapi.net/v1/rgstr",
      Jason.encode!(%{"events" => logs}),
      headers(api_key)
    )
    |> case do
      {:ok, %{status_code: code}} when code < 300 -> {:ok, []}
      _ -> {:error, logs}
    end
  end

  defp headers(api_key) do
    [
      {"STATSIG-API-KEY", api_key},
      {"Content-Type", "application/json"},
      {"STATSIG-SDK-VERSION", "0.0.1"},
      {"STATSIG-SDK-TYPE", "elixir-server"},
      {"STATSIG-CLIENT-TIME", DateTime.utc_now() |> DateTime.to_unix(:millisecond)}
    ]
  end
end
