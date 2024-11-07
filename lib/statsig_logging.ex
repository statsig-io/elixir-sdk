defmodule Statsig.Logging do
  use GenServer
  require Logger

  @type state :: %{
    flush_interval: integer() | nil,
    events: list(),
    flush_timer: reference() | nil
  }

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{
      flush_interval: 60_000,
      events: [],
      flush_timer: nil,
    }, name: __MODULE__)
  end

  def initialize(flush_interval) do
    GenServer.call(__MODULE__, {:initialize, flush_interval})
  end

  def shutdown do
    GenServer.call(__MODULE__, :shutdown)
  end

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_call(:shutdown, _from, state) do
    Logger.info("Shutting down Statsig.Logging")


    new_state = if length(state.events) > 0 do
      Logger.info("Flushing #{length(state.events)} events before shutdown")
      flush_events(state)
    else
      state
    end

    if state.flush_timer, do: Process.cancel_timer(state.flush_timer)

    new_state = %{new_state |
      flush_timer: nil,
      flush_interval: nil,
    }

    {:reply, :ok, new_state}
  end


  @impl true
  def handle_call({:initialize, flush_interval}, _from, state) do
    new_state = if is_number(flush_interval) do
      Map.put(state, :flush_interval, flush_interval)
    else
      state
    end

    new_state = if new_state.flush_interval != nil do
      timer = Process.send_after(__MODULE__, :flush_events, new_state.flush_interval)
      Map.put(new_state, :flush_timer, timer)
    else
      new_state
    end

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:flush, _from, state) do
    new_state = flush_events(state)
    unsent_events = new_state.events
    {:reply, unsent_events, new_state}
  end

  @impl true
  def handle_info(:flush_events, state) do
    new_state = if state.flush_interval != nil do
      timer = Process.send_after(__MODULE__, :flush_events, state.flush_interval)
      Map.put(state, :flush_timer, timer)
    else
      state
    end

    new_state = flush_events(new_state)
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
