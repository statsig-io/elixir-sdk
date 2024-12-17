defmodule Statsig.Configs do
  use GenServer
  require Logger

  @table_name :statsig_configs
  @default_init_timeout :timer.seconds(5)

  defmodule State do
    @default_reload_interval :timer.seconds(10)

    @type t :: %__MODULE__{
            last_sync_time: integer(),
            reload_timer: reference() | nil,
            reload_interval: integer()
          }

    defstruct last_sync_time: 0,
              reload_timer: nil,
              reload_interval: @default_reload_interval

    def new() do
      interval = reload_interval()
      %__MODULE__{reload_interval: interval}
    end

    def schedule_reload(%__MODULE__{} = state) do
      if state.reload_timer != nil do
        Process.cancel_timer(state.reload_timer)
      end
      timer = Process.send_after(self(), :reload_configs, state.reload_interval)
      %__MODULE__{state | reload_timer: timer}
    end

    defp reload_interval() do
      Application.get_env(:statsig, :config_reload_interval, @default_reload_interval)
    end
  end

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def lookup(name, type) do
    :ets.lookup(@table_name, {name, type})
  end

  @impl true
  def init(_) do
    :ets.new(@table_name, [:named_table, :set, :public])
    initial_state = case init_from_bootstrap() do
      {:ok, bootstrap_state} -> bootstrap_state
      :skip -> State.new()
    end

    case attempt_reload(initial_state, init_timeout()) do
      {:ok, updated_state} -> {:ok, State.schedule_reload(updated_state)}
      {:error, _error} -> {:ok, State.schedule_reload(initial_state)}
    end
  end

  @impl true
  def handle_info(:reload_configs, state) do
    case attempt_reload(state) do
      {:ok, updated_state} -> {:noreply, State.schedule_reload(updated_state)}
      {:error, _error} -> {:noreply, State.schedule_reload(state)}
    end
  end

  defp reload_configs(state, timeout) do
    case api_client().download_config_specs(state.last_sync_time, timeout) do
      {:ok, response} ->
        new_time = Map.get(response, "time", 0)

        if new_time >= state.last_sync_time do
          try do
            update_specs(response)
            {:ok, %{state | last_sync_time: new_time}}
          rescue
            error ->
              Logger.error("Failed to update specs: #{inspect(error)}")
              {:ok, state}
          end
        else
          {:ok, state}
        end

      error ->
        {:error, {:reload_failed, error}}
    end
  end

  defp attempt_reload(state, timeout \\ :infinity) do
    case reload_configs(state, timeout) do
      {:ok, updated_state} ->
        {:ok, updated_state}
      {:error, error} ->
        Logger.error("Unexpected error while reloading Statsig configs: #{inspect(error)}")
        {:error, {:reload_failed, error}}
    end
  end

  defp update_configs([], _type), do: :ok

  defp update_configs(configs, type) do
    rows = Enum.map(configs, fn %{"name" => name} = config -> {{name, type}, config} end)
    :ets.insert(@table_name, rows)
  end

  defp api_client, do: Application.get_env(:statsig, :api_client, Statsig.APIClient)

  defp init_from_bootstrap() do
    case Application.get_env(:statsig, :bootstrap_config_specs) do
      nil ->
        :skip
      specs when is_map(specs) ->
        time = update_specs(specs)
        {:ok, %{State.new() | last_sync_time: time}}
      other ->
        Logger.warning("Invalid bootstrap_config_specs format, falling back to network initialization")
        :skip
    end
  end

  defp update_specs(specs) do
    time = Map.get(specs, "time", 0)
    :ets.delete_all_objects(@table_name)

    Map.get(specs, "feature_gates", [])
    |> update_configs(:gate)
    Map.get(specs, "dynamic_configs", [])
    |> update_configs(:config)
    time
  end

  defp init_timeout() do
    Application.get_env(:statsig, :config_init_timeout, @default_init_timeout)
  end
end
