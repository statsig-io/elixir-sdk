defmodule Statsig.Configs do
  use GenServer
  require Logger

  @table_name :statsig_configs

  @type state :: %{
    api_key: String.t() | nil,
    reload_interval: integer(),
    last_sync_time: integer(),
    reload_timer: reference() | nil
  }

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{
      api_key: nil,
      reload_interval: 10000,
      last_sync_time: 0,
      reload_timer: nil,
    }, name: __MODULE__)
  end

  @doc """
  Initializes or reinitializes the configs module with new options.
  Triggers an immediate reload of configs.
  """
  def initialize(options) when is_map(options) do
    GenServer.call(__MODULE__, {:initialize, options})
  end

  @doc """
  Shuts down the configs module, cancelling any pending timers.
  """
  def shutdown do
    GenServer.call(__MODULE__, :shutdown)
  end

  @impl true
  def init(state) do
    # Create ETS table if it doesn't exist
    Logger.info("Creating ETS table: #{@table_name}")
    :ets.new(@table_name, [:named_table, :set, :public])
    {:ok, state}
  rescue
    ArgumentError ->
      Logger.warning("ETS table #{@table_name} already exists")
      {:ok, state}
  end

  @impl true
  def handle_call({:initialize, options}, _from, state) do
    Logger.error("Initializing Configs with options: #{inspect(options)}")

    new_state = state
      |> Map.put(:api_key, options.api_key)
      |> maybe_update_reload_interval(options)

    ensure_table_exists()

    timer = Process.send_after(self(), :reload_configs, new_state.reload_interval)
    Map.put(state, :reload_timer, timer)

    case reload_configs(new_state) do
      {:ok, updated_state} ->
        Logger.error("Config initialization successful")
        {:reply, :ok, updated_state}
      {:error, reason} ->
        Logger.error("Config initialization failed: #{inspect(reason)}")
        {:reply, {:error, :initialization_failed}, new_state}
    end
  end

  @impl true
  def handle_info(:reload_configs, state) do
    # Schedule next reload
    new_state = if state.reload_interval != nil do
      Logger.error("relaod scheduled: #{inspect(state.reload_interval)}")
      timer = Process.send_after(self(), :reload_configs, state.reload_interval)
      Map.put(state, :reload_timer, timer)
    else
      state
    end

    case reload_configs(new_state) do
      {:ok, updated_state} -> {:noreply, updated_state}
      {:error, _reason} -> {:noreply, new_state}
    end
  end

  @impl true
  def handle_call(:shutdown, _from, state) do
    Logger.info("Shutting down Statsig.Configs")
    if state.reload_timer != nil do
      Process.cancel_timer(state.reload_timer)
    end

    new_state = %{state |
      reload_timer: nil,
    }

    {:reply, :ok, new_state}
  end

  def lookup(name, type) do
    ensure_table_exists()  # Ensure table exists before lookup
    :ets.lookup(@table_name, {name, type})
  end

  defp reload_configs(%{api_key: nil} = _state), do: {:error, :no_api_key}
  defp reload_configs(state) do
    ensure_table_exists()  # Ensure table exists before updating
    if state.reload_timer, do: Logger.info("Process timer #{inspect(Process.read_timer(state.reload_timer))}")
    case api_client().download_config_specs(state.api_key, state.last_sync_time) do
      {:ok, response} ->
        new_time = Map.get(response, "time", 0)
        Logger.info("new_time: #{inspect(new_time)}")
        Logger.info("since_time: #{inspect(state.last_sync_time)}")

        if is_number(new_time) and new_time >= state.last_sync_time do
          Logger.info("updating config definitions")
          :ets.delete_all_objects(@table_name)
          response |> Map.get("feature_gates", []) |> save_configs(:gate)
          response |> Map.get("dynamic_configs", []) |> save_configs(:config)

          new_state = state
          |> Map.put(:last_sync_time, new_time || state.last_sync_time)
          {:ok, new_state}
        else
          {:ok, state}
        end
      error ->
        Logger.error("Failed to reload configs: #{inspect(error)}")
        {:error, :reload_failed}
    end
  end

  defp ensure_table_exists do
    unless :ets.whereis(@table_name) != :undefined do
      Logger.info("Recreating ETS table: #{@table_name}")
      :ets.new(@table_name, [:named_table, :set, :public])
    end
  end

  defp save_configs([], _type), do: :ok

  defp save_configs([%{"name" => name} = head | tail], type) when is_binary(name) do
    key = {name, type}
    :ets.insert(@table_name, {key, head})
    save_configs(tail, type)
  end

  defp maybe_update_reload_interval(state, %{reload_interval: interval}) when is_number(interval), do: Map.put(state, :reload_interval, interval)
  defp maybe_update_reload_interval(state, _), do: state

  defp api_client, do: Application.get_env(:statsig, :api_client, Statsig.APIClient)

  @impl true
  def terminate(reason, state) do
    Logger.error("Statsig.Configs terminating. Reason: #{inspect(reason)}, State: #{inspect(state)}")
    :ok
  end
end
