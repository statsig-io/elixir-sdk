defmodule Statsig do
  use GenServer
  alias Statsig.Utils
  require Logger

  # default intervals
  @flush_interval 60_000
  @reload_interval 60_000

  def start_link(opts \\ []) do
    opts =
      opts
      |> Keyword.put_new(:name, __MODULE__)

    GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))
  end

  def init(opts) do
    server = Keyword.fetch!(opts, :name)

    :ets.new(ets_name(server), [:named_table])

    Process.flag(:trap_exit, true)

    state = %{
      api_key: Application.get_env(:statsig, :api_key, nil),
      last_sync: 0,
      events: [],
      tier: Keyword.get(opts, :tier, Application.get_env(:statsig, :env_tier, nil)),
      prefix: server,
      flush_interval: Keyword.get(opts, :flush_interval, @flush_interval),
      reload_interval: Keyword.get(opts, :reload_interval, @reload_interval),
      reload_timer: nil,
      flush_timer: nil
    }
    {:ok, state}
  end

  # TODO - PID should move to be the first argument
  def check_gate(user, gate, server \\ __MODULE__)
  def check_gate(nil, _gate, _server), do: {:error, :no_user}

  def check_gate(user, gate, server) do
    user = Utils.get_user_with_env(user, get_tier(server))

    result = Statsig.Evaluator.eval(user, gate, :gate, server)
    log_exposures(server, user, result.exposures, :gate)

    case result do
      %{reason: :not_found} -> {:error, :not_found}
      _ -> {:ok, result.result}
    end
  end
  # Make a layer module
  # The layer module can take a layer struct and return a value
  # use atoms as keys

  def get_config(user, config, server \\ __MODULE__)
  def get_config(nil, _config, _server), do: {:error, :no_user}

  def get_config(user, config, server) do
    user = Utils.get_user_with_env(user, get_tier(server))
    result = Statsig.Evaluator.eval(user, config, :config, server)
    log_exposures(server, user, result.exposures, :config)

    # TODO - could probably hand back a Result struct
    case result do
      %{reason: :not_found} -> {:error, :not_found}
      # TODO - this be {:ok, result}
      _ -> %{rule_id: Map.get(result.rule, "id"), value: result.value}
    end
  end

  def get_experiment(user, exp), do: get_config(user, exp)
  def get_experiment(user, exp, server), do: get_config(user, exp, server)


  def log_event(event, server \\ __MODULE__) do
    GenServer.call(server, {:log, event})
  end

  def log_event(user, event_name, value, metadata, server \\ __MODULE__) do
    user = Utils.get_user_with_env(user, get_tier(server))
    event = %{
      "eventName" => event_name,
      "value" => value,
      "metadata" => metadata,
      "time" => :os.system_time(:millisecond),
      "user" => Utils.sanitize_user(user)
    }
    GenServer.call(server, {:log, event})
  end


  def state(server \\ __MODULE__), do: GenServer.call(server, :state)

  # TODO - pipeline this
  def lookup(name, type, server \\ __MODULE__), do: :ets.lookup(ets_name(server), {name, type})

  # TODO - pipeline this
  def all(type, server \\ __MODULE__),
    do: :ets.match(ets_name(server), {{:"$1", type}, :_}) |> List.flatten()

  # TODO - will break if the server is a PID
  def ets_name(server) do
    [server, :statsig_store]
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
    event_with_time = Map.update(event, "time", current_time(), fn existing_time ->
      existing_time || current_time()
    end)
    {:reply, :ok, Map.put(state, :events, [event_with_time | state.events])}
  end

  def handle_call(:shutdown, _from, state) do
    handle_flush(state)
    if state.reload_timer, do: Process.cancel_timer(state.reload_timer)
    if state.flush_timer, do: Process.cancel_timer(state.flush_timer)

    {:stop, :normal, :ok, state}
  end

  # TODO add a handle_info for the exit message
  # {:EXIT, <pid>, reason} - if reason is :normal, do nothing
  def handle_info(message, state) do
    case message do
      :initialize ->
        handle_initialize(%{}, state)

      {:initialize, options} ->
        handle_initialize(options, Map.merge(state, options))

      :reload ->
        handle_reload(state)

      :flush ->
        handle_flush(state)

      _ ->
        Logger.warn("Unhandled message in Statsig: #{inspect(message)}")
        {:noreply, state}
    end
  end

  def handle_initialize(options, state) do
    Logger.error("initialize_options: #{inspect(options)}")

    if options[:api_url] do
      Application.put_env(:statsig, :api_url, options[:api_url])
    end

    %{api_key: state_api_key, last_sync: time, prefix: server} = state
    api_key = state_api_key || Application.get_env(:statsig, :api_key)

    %{api_key: api_key, last_sync: time, prefix: server} = state
    {:ok, last_sync} = reload_configs(api_key, time, server)

    reload_interval = options[:reload_interval] || state.reload_interval
    flush_interval = options[:flush_interval] || state.flush_interval

    Logger.info("reload_interval: #{inspect(reload_interval)}")
    Logger.info("flush_interval: #{inspect(flush_interval)}")

    reload_timer = Process.send_after(self(), :reload, reload_interval)
    flush_timer = Process.send_after(self(), :flush, flush_interval)

    updated_state = state
      |> Map.put(:last_sync, last_sync)
      |> Map.put(:reload_interval, reload_interval)
      |> Map.put(:flush_interval, flush_interval)
      |> Map.put(:api_key, api_key)
      |> Map.put(:tier, Application.get_env(:statsig, :env_tier, nil))
      |> Map.put(:reload_timer, reload_timer)
      |> Map.put(:flush_timer, flush_timer)

    {:noreply, updated_state}
  end

  defp handle_reload(state) do
    %{api_key: api_key, last_sync: time, prefix: server, reload_interval: reload_interval} = state
    case reload_configs(api_key, time, server) do
      {:ok, last_sync} ->
        reload_timer = Process.send_after(self(), :reload, reload_interval)
        updated_state = Map.put(state, :last_sync, last_sync)
        |> Map.put(:reload_timer, reload_timer)
        {:noreply, updated_state}

      {:error, :unauthorized} ->
        Logger.error("Unauthorized error. Please check your API key.")
        reload_timer = Process.send_after(self(), :reload, reload_interval)
        {:noreply, Map.put(state, :reload_timer, reload_timer)}

      {:error, _reason} ->
        Logger.error("Failed to reload configs. Will retry in #{reload_interval}ms.")
        reload_timer = Process.send_after(self(), :reload, reload_interval)
        {:noreply, Map.put(state, :reload_timer, reload_timer)}
    end
  end

  defp handle_flush(state) do
    %{api_key: key, events: events, flush_interval: i} = state
    remaining = flush_events(key, events)
    state = Map.put(state, :events, remaining)
    flush_timer = Process.send_after(self(), :flush, state.flush_interval)
    {:noreply, state |> Map.put(:flush_timer, flush_timer)}
  end

  def terminate(_reason, %{api_key: key, events: events}) do
    Logger.info("for now, do nothing on terminate")
  end

  defp get_tier(server) do
    case state(server) do
      %{tier: t} -> t
      _ -> nil
    end
  end


  defp current_time do
    DateTime.utc_now() |> DateTime.to_unix(:millisecond)
  end

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
    Logger.info("reload_configs triggered")
    case api_client().download_config_specs(api_key, since) do
      {:ok, config} ->
        new_time = Map.get(config, "time", 0)
        Logger.info("new_time: #{inspect(new_time)}")
        Logger.info("since_time: #{inspect(since)}")

        if is_number(new_time) and new_time > since do
          config |> Map.get("feature_gates", []) |> save_configs(:gate, server)
          config |> Map.get("dynamic_configs", []) |> save_configs(:config, server)
          {:ok, new_time}
        else
          {:ok, since}
        end

      {:error, :unauthorized} ->
        Logger.error("Unauthorized error when downloading config specs")
        {:error, :unauthorized}

      {:error, :unexpected_error, error} ->
        Logger.error("Unexpected error when downloading config specs")
        {:error, :unexpected_error}

      {:error, reason} ->
        Logger.error("Error when downloading config specs: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def flush(server \\ __MODULE__), do: GenServer.call(server, :flush)
  def shutdown(server \\ __MODULE__), do: GenServer.call(server, :shutdown)

  defp flush_events(_key, []), do: []

  defp flush_events(key, events) do
    # send in batches; keep any that fail
    unsent = events
    |> Enum.chunk_every(500)
    |> Enum.reduce([], fn chunk, unsent ->
      {result, failed} = api_client().push_logs(key, chunk)
      failed ++ unsent
    end)
    unsent
  end

  defp save_configs([], _, _), do: :ok

  defp save_configs([%{"name" => name} = head | tail], type, server) when is_binary(name) do
    :ets.insert(ets_name(server), {{name, type}, head})
    save_configs(tail, type, server)
  end

  # config has no name, so skip it
  defp save_configs([_head | tail], type, server), do: save_configs(tail, type, server)

  # should maybe accept this as part of initialization, too, so different pids can use different clients
  defp api_client, do: Application.get_env(:statsig, :api_client, Statsig.APIClient)
end
