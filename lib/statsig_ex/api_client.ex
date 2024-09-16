defmodule StatsigEx.APIClient do

  def download_config_specs(api_key, since_time \\ 0) do
    url = "https://api.statsigcdn.com/v1/download_config_specs/#{api_key}.json?sinceTime=#{since_time}"

    case Req.get(url: url, headers: headers(api_key)) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}
      {:ok, %Req.Response{status: status}} when status != 200 ->
        {:error, :http_error, status}
    end
  end

  def push_logs(api_key, logs) do
    Req.post(
      url: "https://statsigapi.net/v1/rgstr",
      json: %{"events" => logs},
      headers: headers(api_key)
    )
    |> case do
      {:ok, %{status: code}} when code < 300 -> {:ok, []}
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
