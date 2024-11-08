defmodule Statsig.Configs do
  use GenServer
  require Logger

  @table_name :statsig_configs

  @type state :: %{
    last_sync_time: integer(),
    reload_timer: reference() | nil
  }

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{
      last_sync_time: 0,
      reload_timer: nil,
    }, name: __MODULE__)
  end

  @impl true
  def init(state) do
    Logger.error("Initializing Statsig.Configs #{inspect(Application.get_all_env(:statsig))}")
    Logger.error("Stacktrace: #{inspect(Process.info(self(), :current_stacktrace))}")
    :ets.new(@table_name, [:named_table, :set, :public])
    timer = state.reload_timer || Process.send_after(self(), :reload_configs, get_reload_interval())
    new_state = Map.put(state, :reload_timer, timer)

    case reload_configs(new_state) do
      {:ok, updated_state} -> {:ok, updated_state}
      {:error, :reload_failed, _error} -> {:ok, state}
      {:error, reason} -> {:ok, state}
    end
  end

  @impl true
  def handle_info(:reload_configs, state) do
    timer = Process.send_after(self(), :reload_configs, get_reload_interval())
    new_state = Map.put(state, :reload_timer, timer)

    case reload_configs(new_state) do
      {:ok, updated_state} -> {:noreply, updated_state}
      {:error, :reload_failed, _error} -> {:noreply, state}
      {:error, _reason} -> {:noreply, new_state}
    end
  end

  def lookup(name, type) do
    :ets.lookup(@table_name, {name, type})
  end

  defp reload_configs(state) do
    case api_client().download_config_specs(state.last_sync_time) do
      {:ok, response} ->
        new_time = Map.get(response, "time", 0)

        if new_time >= state.last_sync_time do
          :ets.delete_all_objects(@table_name)
          response |> Map.get("feature_gates", []) |> update_configs(:gate)
          response |> Map.get("dynamic_configs", []) |> update_configs(:config)

          {:ok, Map.put(state, :last_sync_time, new_time)}
        else
          {:ok, state}
        end
      error ->
        {:error, :reload_failed, error}
    end
  end

  defp get_reload_interval() do
    Application.get_env(:statsig, :config_reload_interval, 10_000)
  end

  defp update_configs([], _type), do: :ok

  defp update_configs(configs, type) do
    rows = Enum.map(configs, fn %{"name" => name} = config -> {{name, type}, config} end)
    :ets.insert(@table_name, rows)
  end

  defp api_client, do: Application.get_env(:statsig, :api_client, Statsig.APIClient)

end
