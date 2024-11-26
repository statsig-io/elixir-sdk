defmodule Statsig.APIClient do
  require Logger
  @default_logging_api_url "https://statsigapi.net/v1"
  @default_config_specs_api_url "https://api.statsigcdn.com/v1"

  def download_config_specs(since_time \\ 0) do
    case api_key() do
      {:ok, key} ->
        base_url = api_url(@default_config_specs_api_url)

        url =
          URI.new!(base_url)
          |> URI.append_path(Path.join("/download_config_specs", key <> ".json"))
          |> URI.append_query(URI.encode_query(sinceTime: to_string(since_time)))
          |> URI.to_string()

        case Req.get(url: url, headers: headers(key)) do
          {:ok, %Req.Response{status: status, body: %{} = body}} when status in 200..299 ->
            {:ok, body}

          {:ok, %Req.Response{status: status} = response} when status in 200..299 ->
            Logger.error("Invalid response format, expected map got: #{inspect(response.body)}")
            {:error, {:invalid_response_format, response.body}}

          {:ok, %Req.Response{status: status, body: body}} ->
            Logger.error("HTTP error: status #{status}, body: #{inspect(body)}")
            {:error, :http_error, status}

          {:error, error} ->
            Logger.error("Unexpected error: #{inspect(error)}")
            {:error, :unexpected_error, error}
        end

      {:error, reason} ->
        Logger.error("Failed to get API key: #{reason}")
        {:error, :missing_api_key, reason}
    end
  end

  def push_logs(logs) do
    case api_key() do
      {:ok, key} ->
        base_url = api_url(@default_logging_api_url)

        url =
          URI.new!(base_url)
          |> URI.append_path("/rgstr")
          |> URI.to_string()

        case Req.post(url: url, json: %{events: logs}, headers: headers(key)) do
          {:ok, %{status: status}} when status in 200..299 ->
            {:ok, []}

          {:ok, response} ->
            truncated_body = response.body |> inspect() |> String.slice(0..200)
            Logger.error(
              "Failed to push logs: status #{response.status}, body: #{truncated_body}"
            )

            {:error, logs}

          {:error, error} ->
            Logger.error("Failed to push logs: #{inspect(error)}")
            {:error, logs}
        end

      {:error, reason} ->
        Logger.error("Failed to get API key: #{reason}")
        {:error, logs}
    end
  end

  defp api_key() do
    case Application.get_env(:statsig, :api_key) do
      nil ->
        raise "Statsig API key is not configured. Please set the :api_key in your :statsig configuration."

      key when is_binary(key) ->
        {:ok, key}

      key ->
        raise "Invalid Statsig API key format: #{inspect(key)}. API key must be a string."
    end
  end

  defp api_url(default_url) do
    url = Application.get_env(:statsig, :api_url, default_url)
    if String.ends_with?(url, "/"), do: url, else: url <> "/"
  end

  defp headers(key) do
    [
      {"STATSIG-API-KEY", key},
      {"Content-Type", "application/json"},
      {"STATSIG-SDK-VERSION", "0.0.1"},
      {"STATSIG-SDK-TYPE", "elixir-server"},
      {"STATSIG-CLIENT-TIME", System.system_time(:millisecond)}
    ]
  end
end
