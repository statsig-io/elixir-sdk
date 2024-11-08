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

  def initialize() do
    GenServer.call(__MODULE__, {:initialize})
  end

  @impl true
  def init(state) do
    :ets.new(@table_name, [:named_table, :set, :public])
    case Application.get_env(:statsig, :api_key) do
      key when is_binary(key) and byte_size(key) > 0 ->
        case do_initialize(state) do
          {:ok, new_state} -> {:ok, new_state}
          {:error, _reason} -> {:ok, state}
        end
      _ ->
        {:ok, state}
    end
  rescue
    ArgumentError ->
      {:ok, state}
  end

  @impl true
  def handle_call({:initialize}, _from, state) do
    if state.reload_timer != nil do
      {:ok, state}
    end
    case do_initialize(state) do
      {:ok, new_state} -> {:reply, :ok, new_state}
      {:error, _reason} -> {:reply, :ok, state}
    end
  end

  @impl true
  def handle_info(:reload_configs, state) do
    timer = Process.send_after(self(), :reload_configs, get_reload_interval())
    new_state = Map.put(state, :reload_timer, timer)

    case reload_configs(new_state) do
      {:ok, updated_state} -> {:noreply, updated_state}
      {:error, _reason} -> {:noreply, new_state}
    end
  end

  def lookup(name, type) do
    ensure_table_exists()
    :ets.lookup(@table_name, {name, type})
  end

  defp do_initialize(state) do
    timer = state.reload_timer || Process.send_after(self(), :reload_configs, get_reload_interval())
    new_state = Map.put(state, :reload_timer, timer)

    case reload_configs(new_state) do
      {:ok, updated_state} -> {:ok, updated_state}
      {:error, reason} -> {:error, :initialization_failed}
    end
  end

  defp reload_configs(state) do
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

  defp get_reload_interval() do
    Application.get_env(:statsig, :config_reload_interval, 10_000)
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
