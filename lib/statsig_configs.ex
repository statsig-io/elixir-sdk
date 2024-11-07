defmodule Statsig.Configs do
  use GenServer
  require Logger

  @table_name :statsig_configs

  @type state :: %{
    reload_interval: integer(),
    last_sync_time: integer(),
    reload_timer: reference() | nil
  }

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{
      reload_interval: 10_000,
      last_sync_time: 0,
      reload_timer: nil,
    }, name: __MODULE__)
  end

  def initialize(reload_interval) do
    GenServer.call(__MODULE__, {:initialize, reload_interval})
  end

  def shutdown do
    GenServer.call(__MODULE__, :shutdown)
  end

  @impl true
  def init(state) do
    :ets.new(@table_name, [:named_table, :set, :public])
    {:ok, state}
  rescue
    ArgumentError ->
      {:ok, state}
  end

  @impl true
  def handle_call({:initialize, reload_interval}, _from, state) do
    new_state = if is_number(reload_interval) do
      Map.put(state, :reload_interval, reload_interval)
    else
      state
    end

    ensure_table_exists()

    timer = Process.send_after(self(), :reload_configs, new_state.reload_interval)
    Map.put(state, :reload_timer, timer)

    case reload_configs(new_state) do
      {:ok, updated_state} ->
        {:reply, :ok, updated_state}
      {:error, reason} ->
        {:reply, {:error, :initialization_failed}, new_state}
    end
  end

  @impl true
  def handle_info(:reload_configs, state) do
    new_state = if state.reload_interval != nil do
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
    if state.reload_timer != nil do
      Process.cancel_timer(state.reload_timer)
    end

    new_state = %{state |
      reload_timer: nil,
    }

    {:reply, :ok, new_state}
  end

  def lookup(name, type) do
    ensure_table_exists()
    :ets.lookup(@table_name, {name, type})
  end

  @impl true
  def terminate(reason, state) do
    :ok
  end

  defp reload_configs(state) do
    ensure_table_exists()

    case api_client().download_config_specs(state.last_sync_time) do
      {:ok, response} ->
        new_time = Map.get(response, "time", 0)

        if is_number(new_time) and new_time >= state.last_sync_time do
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
        {:error, :reload_failed}
    end
  end

  defp ensure_table_exists do
    unless :ets.whereis(@table_name) != :undefined do
      :ets.new(@table_name, [:named_table, :set, :public])
    end
  end

  defp save_configs([], _type), do: :ok

  defp save_configs([%{"name" => name} = head | tail], type) when is_binary(name) do
    key = {name, type}
    :ets.insert(@table_name, {key, head})
    save_configs(tail, type)
  end

  defp api_client, do: Application.get_env(:statsig, :api_client, Statsig.APIClient)

end
