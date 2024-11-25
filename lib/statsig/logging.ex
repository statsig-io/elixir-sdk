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
        events: [],
        flush_timer: nil,
        flush_interval: flush_interval()
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

    def flush_events(%__MODULE__{events: []} = state), do: {state, []}

    def flush_events(%__MODULE__{events: events} = state) do
      {failed_events, successful_events} =
        events
        |> Enum.chunk_every(500)
        |> Enum.reduce({[], []}, fn chunk, {failed, successful} ->
          case api_client().push_logs(chunk) do
            {:ok, _} ->
              {failed, [successful, chunk]}

            {:error, reason} ->
              Logger.error("Failed to flush events: #{inspect(reason)}")
              {[failed, chunk], successful}
          end
        end)

      {%{state | events: List.flatten(failed_events)}, List.flatten(successful_events)}
    end

    defp flush_interval() do
      Application.get_env(:statsig, :logging_flush_interval, 60_000)
    end

    defp api_client, do: Application.get_env(:statsig, :api_client, Statsig.APIClient)

    def schedule_flush(state) do
      if state.flush_timer do
        Process.cancel_timer(state.flush_timer)
      end
      timer = Process.send_after(Statsig.Logging, :flush_events, state.flush_interval)
      %{state | flush_timer: timer}
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
    {:ok, State.schedule_flush(state)}
  end

  @impl true
  def handle_call(:flush, _from, state) do
    {new_state, _} = State.flush_events(state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info(:flush_events, state) do
    {new_state, _} = State.flush_events(State.schedule_flush(state))
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:log_event, event}, state) do
    {:noreply, State.add_event(state, event)}
  end

  @impl true
  def terminate(reason, state) do
    # best effort
    {_, _} = State.flush_events(state)
    :ok
  end
end
