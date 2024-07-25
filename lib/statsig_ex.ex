defmodule StatsigEx do
  use GenServer
  alias StatsigEx.Utils

  # default intervals
  @flush_interval 60_000
  @reload_interval 60_000

  def start_link(opts \\ []) do
    opts =
      opts
      |> Keyword.put_new(:api_key, get_api_key_opt(opts))
      |> Keyword.put_new(:name, __MODULE__)

    GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))
  end

  def init(opts) do
    server = Keyword.fetch!(opts, :name)
    :ets.new(ets_name(server), [:named_table])

    # so we can try to flush events before shutdown
    Process.flag(:trap_exit, true)

    state = %{
      api_key: get_api_key(Keyword.fetch!(opts, :api_key)),
      last_sync: 0,
      events: [],
      tier: Keyword.get(opts, :tier, Application.get_env(:statsig_ex, :env_tier, nil)),
      prefix: server,
      flush_interval: Keyword.get(opts, :flush_interval, @flush_interval),
      reload_interval: Keyword.get(opts, :reload_interval, @reload_interval)
    }

    # if the api key is blank, we should probably just shutdown
    # case state.api_key do
    #   v when v in [nil, ""] ->
    #     {:stop, :normal}

    #   _ ->
    {:ok, last_sync} = reload_configs(state.api_key, state.last_sync, server)

    # reload every 60s by default
    Process.send_after(self(), :reload, state.reload_interval)
    Process.send_after(self(), :flush, state.flush_interval)
    {:ok, Map.put(state, :last_sync, last_sync)}
    # end
  end

  # should we support default value?
  # when would we fallback to it, only when the flag doesn't exist?
  def check_gate(user, gate, server \\ __MODULE__)
  def check_gate(nil, _gate, _server), do: {:error, :no_user}

  def check_gate(user, gate, server) do
    user = Utils.get_user_with_env(user, get_tier(server))

    result = StatsigEx.Evaluator.eval(user, gate, :gate, server)
    log_exposures(server, user, result.exposures, :gate)

    case result do
      %{reason: :not_found} -> {:error, :not_found}
      _ -> {:ok, result.result}
    end

    # result.result
  end

  def get_config(user, config, server \\ __MODULE__)
  def get_config(nil, _config, _server), do: {:error, :no_user}

  def get_config(user, config, server) do
    user = Utils.get_user_with_env(user)
    result = StatsigEx.Evaluator.eval(user, config, :config, server)
    log_exposures(server, user, result.exposures, :config)

    # could probably hand back a Result struct
    case result do
      %{reason: :not_found} -> {:error, :not_found}
      _ -> %{rule_id: Map.get(result.rule, "id"), value: result.value}
    end
  end

  def get_experiment(user, exp), do: get_config(user, exp)
  def get_experiment(user, exp, server), do: get_config(user, exp, server)

  def state(server \\ __MODULE__), do: GenServer.call(server, :state)

  def lookup(name, type, server \\ __MODULE__), do: :ets.lookup(ets_name(server), {name, type})

  def all(type, server \\ __MODULE__),
    do: :ets.match(ets_name(server), {{:"$1", type}, :_}) |> List.flatten()

  def ets_name(server) do
    [server, :statsig_ex_store]
    |> Enum.join("_")
    |> String.replace(".", "_")
    |> String.to_atom()
  end

  # for debugging
  def handle_call(:state, _from, state), do: {:reply, state, state}

  def handle_call(:flush, _from, %{api_key: key, events: events} = state) do
    unsent = flush_events(key, events)
    {:reply, unsent, Map.put(state, :events, unsent)}
  end

  def handle_call({:log, event}, _from, state) do
    {:reply, :ok, Map.put(state, :events, [event | state.events])}
  end

  def handle_info(
        :reload,
        %{api_key: key, last_sync: time, prefix: server, reload_interval: i} = state
      ) do
    {:ok, sync_time} = reload_configs(key, time, server)
    Process.send_after(self(), :reload, i)
    {:noreply, Map.put(state, :last_sync, sync_time)}
  end

  def handle_info(:flush, %{api_key: key, events: events, flush_interval: i} = state) do
    remaining = flush_events(key, events)
    Process.send_after(self(), :flush, i)
    {:noreply, Map.put(state, :events, remaining)}
  end

  def terminate(_reason, %{api_key: key, events: events}), do: flush_events(key, events)

  defp get_api_key_opt(opts) do
    opts
    |> Keyword.fetch(:api_key)
    |> case do
      {:ok, k} ->
        k

      _ ->
        case Application.get_env(:statsig, :api_key) do
          nil -> {:system, "STATSIG_API_KEY"}
          v -> v
        end
    end
  end

  defp get_tier(server) do
    case state(server) do
      %{tier: t} -> t
      _ -> nil
    end
  end

  # shouldn't log anything...
  defp log_exposures(_server, _user, [], _type), do: :ok

  defp log_exposures(server, user, [%{"gate" => c, "ruleID" => r} | secondary], :config) do
    primary = %{
      "config" => c,
      "ruleID" => r
    }

    event =
      base_event(user, secondary, :config)
      |> Map.put("metadata", primary)

    GenServer.call(server, {:log, event})
  end

  defp log_exposures(server, user, [primary | secondary], type) do
    event =
      base_event(user, secondary, type)
      |> Map.put("metadata", primary)

    GenServer.call(server, {:log, event})
  end

  defp base_event(user, secondary, type) do
    user = Utils.sanitize_user(user)

    %{
      "eventName" => "statsig::#{type}_exposure",
      "secondaryExposures" => secondary,
      "time" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
      "user" => user
    }
  end

  defp reload_configs(api_key, since, server) do
    # call Statsig API to get configs (eventually we can make the http client configurable)
    # should probably crash on startup but be resilient on reload; will fix later
    {:ok, config} = api_client().download_config_specs(api_key, since)

    config |> Map.get("feature_gates", []) |> save_configs(:gate, server)
    config |> Map.get("dynamic_configs", []) |> save_configs(:config, server)

    # return the time of this last fetch
    {:ok, Map.get(config, "time", since)}
  end

  def flush(server \\ __MODULE__), do: GenServer.call(server, :flush)

  defp flush_events(_key, []), do: []

  defp flush_events(key, events) do
    # send in batches; keep any that fail
    events
    |> Enum.chunk_every(500)
    |> Enum.reduce([], fn chunk, unsent ->
      {:ok, failed} = api_client().push_logs(key, chunk)
      [failed | unsent]
    end)
    |> List.flatten()
  end

  defp get_api_key({atom, var}) when atom in [:system, :env], do: System.get_env(var)
  defp get_api_key(key), do: key

  defp save_configs([], _, _), do: :ok

  defp save_configs([%{"name" => name} = head | tail], type, server) when is_binary(name) do
    :ets.insert(ets_name(server), {{name, type}, head})
    save_configs(tail, type, server)
  end

  # config has no name, so skip it
  defp save_configs([_head | tail], type, server), do: save_configs(tail, type, server)

  # should maybe accept this as part of initialization, too, so different pids can use different clients
  defp api_client, do: Application.get_env(:statsig_ex, :api_client, StatsigEx.APIClient)
end
