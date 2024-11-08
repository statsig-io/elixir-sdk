defmodule Statsig.APIClient do
  require Logger
  @default_logging_api_url "https://statsigapi.net/v1/"
  @default_config_specs_api_url "https://api.statsigcdn.com/v1/"

  def download_config_specs(since_time \\ 0) do
    base_url = get_api_url(@default_config_specs_api_url)
    url = "#{base_url}download_config_specs/#{get_api_key()}.json?sinceTime=#{since_time}"

    result = Req.get(url: url)

    case result do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        if is_map(body) do
          {:ok, body}
        else
          Logger.error("Invalid response format, expected map got: #{inspect(body)}")
          {:error, :invalid_response_format, body}
        end
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
    base_url = get_api_url(@default_logging_api_url)
    url = "#{base_url}rgstr"

    Req.post(
      url: url,
      json: %{"events" => logs},
      headers: headers(get_api_key())
    ) |> case do
      {:ok, %{status: code}} when code < 300 -> {:ok, []}
      _ -> {:error, logs}
    end
  end

  defp get_api_key() do
    Application.get_env(:statsig, :api_key)
  end

  defp get_api_url(default_url) do
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
