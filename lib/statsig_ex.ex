defmodule StatsigEx do
  use GenServer
  alias StatsigEx.Utils

  # we might need to allow for a name to be passed so we can test things
  def start_link(opts \\ []) do
    # should pull from an env var here
    opts = Keyword.put_new(opts, :api_key, {:env, "STATSIG_API_KEY"})

    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    :ets.new(ets_name(), [:named_table])

    state = %{
      api_key: get_api_key(Keyword.fetch!(opts, :api_key)),
      last_sync: 0,
      events: []
    }

    {:ok, last_sync} = reload_configs(state.api_key, state.last_sync)

    # reload every 60s
    Process.send_after(self(), :reload, 60_000)
    {:ok, Map.put(state, :last_sync, last_sync)}
  end

  def check_gate(user, gate) do
    user = Utils.get_user_with_env(user)

    {result, _raw_result, _value, _rule, exposures} = StatsigEx.Evaluator.eval(user, gate, :gate)

    log_exposures(user, exposures, :gate)
    result
  end

  def get_config(user, config) do
    user = Utils.get_user_with_env(user)

    {_result, _raw_result, value, rule, exposures} =
      StatsigEx.Evaluator.eval(user, config, :config)

    log_exposures(user, exposures, :config)

    %{rule_id: Map.get(rule, "id"), value: value}
  end

  def get_experiment(user, exp), do: get_config(user, exp)

  def state, do: GenServer.call(__MODULE__, :state)

  def lookup(name, type), do: :ets.lookup(ets_name(), {name, type})
  def all(type), do: :ets.match(ets_name(), {{:"$1", type}, :_}) |> List.flatten()

  def ets_name, do: :statsig_ex_store

  # for debugging
  def handle_call(:state, _from, state) do
    {:reply, state, state}
  end

  def handle_call(:flush, _from, %{api_key: key, events: events} = state) do
    unsent = flush_events(key, events)
    {:reply, unsent, Map.put(state, :events, unsent)}
  end

  def handle_call({:log, event}, _from, state) do
    # for now, just throw things in there, don't worry about the shape
    {:reply, :ok, Map.put(state, :events, [event | state.events])}
  end

  def handle_info(:reload, %{api_key: key, last_sync: time} = state) do
    {:ok, sync_time} = reload_configs(key, time)
    IO.puts("reloading!")
    Process.send_after(self(), :reload, 60_000)
    {:noreply, Map.put(state, :last_sync, sync_time)}
  end

  def handle_info(:flush, %{api_key: key, events: events} = state) do
    remaining = flush_events(key, events)
    {:noreply, Map.put(state, :events, remaining)}
  end

  # shouldn't log anything...
  defp log_exposures(_user, [], _type), do: :ok

  defp log_exposures(user, [primary | secondary], _type) do
    user = Utils.sanitize_user(user)

    event = %{
      "eventName" => "statsig::gate_exposure",
      "metadata" => primary,
      "secondaryExposures" => secondary,
      "time" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
      "user" => user
    }

    GenServer.call(__MODULE__, {:log, event})
  end

  defp reload_configs(api_key, since) do
    # call Statsig API to get configs (eventually we can make the http client configurable)
    # should probably crash on startup but be resilient on reload; will fix later
    {:ok, config} = api_client().download_config_specs(api_key, since)

    config |> Map.get("feature_gates", []) |> save_configs(:gate)
    config |> Map.get("dynamic_configs", []) |> save_configs(:config)

    # return the time of this last fetch
    {:ok, Map.get(config, "time", since)}
  end

  def flush, do: GenServer.call(__MODULE__, :flush)

  defp flush_events(_key, []), do: []

  defp flush_events(key, events) do
    # send in batches; keep any that fail
    events
    |> Enum.chunk_every(500)
    |> Enum.reduce([], fn chunk, unsent ->
      # this probably doesn't work yet, but I'm not really worried about it right now
      {:ok, resp} = api_client().push_logs(key, chunk)
      [resp | unsent]
    end)
    |> List.flatten()
  end

  defp get_api_key({:env, var}), do: System.get_env(var)
  defp get_api_key(key), do: key

  defp save_configs([], _), do: :ok

  defp save_configs([%{"name" => name} = head | tail], type) when is_binary(name) do
    :ets.insert(ets_name(), {{name, type}, head})
    save_configs(tail, type)
  end

  defp save_configs([_head | tail], type), do: save_configs(tail, type)

  defp api_client, do: Application.get_env(:statsig_ex, :api_client, StatsigEx.APIClient)
end
