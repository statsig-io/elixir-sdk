defmodule Statsig.APIClient do
  require Logger
  @default_logging_api_url "https://statsigapi.net/v1"
  @default_config_specs_api_url "https://api.statsigcdn.com/v1"

  def download_config_specs(since_time \\ 0) do
    base_url = api_url(@default_config_specs_api_url)

    url = URI.new!(base_url)
    |> URI.append_path("/download_config_specs/#{api_key()}.json")
    |> URI.append_query(URI.encode_query(sinceTime: since_time))
    |> URI.to_string()

    Logger.error("downloading config specs from #{url}")

    result = Req.get(url: url)

    case result do
      {:ok, %Req.Response{status: status, body: %{} = body}} when status in 200..299 ->
        {:ok, body}
      {:ok, %Req.Response{status: status} = response} when status in 200..299 ->
        Logger.error("Invalid response format, expected map got: #{inspect(response.body)}")
        {:error, {:invalid_response_format, response.body}}
      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("HTTP error: status #{status}, body: #{inspect(body)}")
        {:error, :http_error, status}
      {:error, :unexpected_error, error} ->
        Logger.error("Unexpected error: #{inspect(error)}")
        {:error, :unexpected_error, error}
      {:error, error} ->
        Logger.error("Unexpected error: #{inspect(error)}")
        {:error, :unexpected_error, error}
    end
  end

  def push_logs(logs) do
    base_url = api_url(@default_logging_api_url)

    url = URI.new!(base_url)
    |> URI.append_path("/rgstr")
    |> URI.to_string()

    Req.post(
      url: url,
      json: %{"events" => logs},
      headers: headers(api_key())
    ) |> case do
      {:ok, %{status: code}} when code < 300 -> {:ok, []}
      {:ok, response} ->
        Logger.error("Failed to push logs: status #{response.status}, body: #{inspect(response.body)}")
        {:error, logs}
      {:error, error} ->
        Logger.error("Failed to push logs: #{inspect(error)}")
        {:error, logs}
    end
  end

  defp api_key() do
    # Application.get_env(:statsig, :api_key)
    "secret-CP6EOotVVs6oKO6tITIcfCdul8P4X5aCNgikbQDxCud"
  end

  defp api_url(default_url) do
    url = Application.get_env(:statsig, :api_url, default_url)
    if String.ends_with?(url, "/"), do: url, else: url <> "/"
  end

  defp headers(api_key) do
    [
      {"STATSIG-API-KEY", api_key},
      {"Content-Type", "application/json"},
      {"STATSIG-SDK-VERSION", "0.0.1"},
      {"STATSIG-SDK-TYPE", "elixir-server"},
      {"STATSIG-CLIENT-TIME", :os.system_time(:millisecond)}
    ]
  end

end
