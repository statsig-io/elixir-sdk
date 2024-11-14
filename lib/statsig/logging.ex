defmodule Statsig.Logging do
  use GenServer
  require Logger

  defmodule State do
    defstruct events: [], flush_timer: nil, flush_interval: 60_000

    @type t :: %__MODULE__{
      events: list(),
      flush_timer: reference() | nil,
      flush_interval: integer()
    }

    def new(opts \\ []) do
      %__MODULE__{
        events: Keyword.get(opts, :events, []),
        flush_timer: Keyword.get(opts, :flush_timer),
        flush_interval: Application.get_env(:statsig, :logging_flush_interval, 60_000)
      }
    end

    def add_event(state, event) do
      %{state | events: [event | state.events]}
    end

    def set_timer(state, timer) do
      %{state | flush_timer: timer}
    end

    def clear_events(state) do
      %{state | events: []}
    end
  end

  def start_link(_) do
    GenServer.start_link(__MODULE__, State.new(), name: __MODULE__)
  end

  def log_event(event) do
    GenServer.cast(__MODULE__, {:log_event, event})
  end

  def flush do
    GenServer.call(__MODULE__, :flush)
  end

  @impl true
  def init(state) do
    timer = Process.send_after(__MODULE__, :flush_events, state.flush_interval)
    {:ok, State.set_timer(state, timer)}
  end

  @impl true
  def handle_call(:flush, _from, state) do
    new_state = flush_events(state)
    unsent_events = new_state.events
    {:reply, unsent_events, new_state}
  end

  @impl true
  def handle_info(:flush_events, state) do
    timer = Process.send_after(__MODULE__, :flush_events, state.flush_interval)
    new_state = flush_events(State.set_timer(state, timer))
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:log_event, event}, state) do
    {:noreply, State.add_event(state, event)}
  end

  @impl true
  def terminate(reason, state) do
    flush_events(state)

    :ok
  end

  defp flush_events(%State{events: []} = state), do: state
  defp flush_events(state) do
    case api_client().push_logs(state.events) do
      {:ok, _} -> State.clear_events(state)
      {:error, reason} ->
        Logger.error("Failed to flush events: #{inspect(reason)}")
        state
    end
  end


  defp api_client, do: Application.get_env(:statsig, :api_client, Statsig.APIClient)

end
