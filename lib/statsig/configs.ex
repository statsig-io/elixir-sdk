defmodule Statsig.Configs do
  use GenServer
  require Logger

  @table_name :statsig_configs
  @default_reload_interval :timer.seconds(10)

  defmodule State do
    @type t :: %__MODULE__{
            last_sync_time: integer(),
            reload_timer: reference() | nil,
            reload_interval: integer()
          }

    defstruct last_sync_time: 0,
              reload_timer: nil,
              reload_interval: @default_reload_interval

    def new() do
      %__MODULE__{reload_interval: reload_interval()}
    end

    def schedule_reload(%__MODULE__{} = state) do
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
    initial_state = State.new()

    case attempt_reload(initial_state) do
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

  defp reload_configs(state) do
    case api_client().download_config_specs(state.last_sync_time) do
      {:ok, response} ->
        new_time = Map.get(response, "time", 0)

        if new_time >= state.last_sync_time do
          :ets.delete_all_objects(@table_name)
          response |> Map.get("feature_gates", []) |> update_configs(:gate)
          response |> Map.get("dynamic_configs", []) |> update_configs(:config)

          {:ok, %{state | last_sync_time: new_time}}
        else
          {:ok, state}
        end

      error ->
        {:error, {:reload_failed, error}}
    end
  end

  defp attempt_reload(state) do
    case reload_configs(state) do
      {:ok, updated_state} ->
        {:ok, updated_state}
      {:error, error} ->
        Logger.error("Unexpected error while reloading Statsig configs: #{inspect(error)}")
        {:error, {:reload_failed, error}}
    end
  end

  defp reload_interval() do
    Application.get_env(:statsig, :config_reload_interval, 10_000)
  end

  defp update_configs([], _type), do: :ok

  defp update_configs(configs, type) do
    rows = Enum.map(configs, fn %{"name" => name} = config -> {{name, type}, config} end)
    :ets.insert(@table_name, rows)
  end

  defp api_client, do: Application.get_env(:statsig, :api_client, Statsig.APIClient)
end
