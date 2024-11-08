defmodule Statsig.Logging do
  use GenServer
  require Logger

  @type state :: %{
    events: list(),
    flush_timer: reference() | nil
  }

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{
      events: [],
      flush_timer: nil,
    }, name: __MODULE__)
  end

  def initialize() do
    GenServer.call(__MODULE__, {:initialize})
  end

  def flush do
    GenServer.call(__MODULE__, :flush)
  end

  @impl true
  def init(state) do
    case Application.get_env(:statsig, :api_key) do
      key when is_binary(key) and byte_size(key) > 0 ->
        timer = Process.send_after(__MODULE__, :flush_events, get_flush_interval())
        {:ok, Map.put(state, :flush_timer, timer)}
      _ ->
        {:ok, state}
    end
    {:ok, state}
  end

  @impl true
  def handle_call({:initialize}, _from, state) do
    timer = state.flush_timer || Process.send_after(__MODULE__, :flush_events, get_flush_interval())

    {:reply, :ok, Map.put(state, :flush_timer, timer)}
  end

  @impl true
  def handle_call(:flush, _from, state) do
    new_state = flush_events(state)
    unsent_events = new_state.events
    {:reply, unsent_events, new_state}
  end

  @impl true
  def handle_info(:flush_events, state) do
    timer = Process.send_after(__MODULE__, :flush_events, get_flush_interval())

    new_state = flush_events(Map.put(state, :flush_timer, timer))
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:log_event, event}, state) do
    new_events = [event | state.events]
    new_state = %{state | events: new_events}
    {:noreply, new_state}
  end

  @impl true
  def terminate(reason, state) do
    if length(state.events) > 0 do
      flush_events(state)
    end

    :ok
  end

  defp get_flush_interval() do
    Application.get_env(:statsig, :logging_flush_interval, 60_000)
  end

  defp flush_events(%{events: []} = state), do: state
  defp flush_events(state) do
    case api_client().push_logs(state.events) do
      {:ok, _} ->
        %{state | events: []}
      {:error, reason} ->
        Logger.error("Failed to flush events: #{inspect(reason)}")
        state
    end
  end


  defp api_client, do: Application.get_env(:statsig, :api_client, Statsig.APIClient)

end
