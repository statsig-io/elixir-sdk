defmodule Statsig do
  use GenServer
  alias Statsig.Utils
  require Logger

  # default intervals
  @flush_interval 60_000
  @reload_interval 60_000

  @config_store :statsig_store
  @log_queue :statsig_log_queue

  def start_link(opts \\ []) do
    opts =
      opts
      |> Keyword.put_new(:name, __MODULE__)

    GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))
  end

  def init(opts) do
    server = Keyword.fetch!(opts, :name)

    :ets.new(@config_store, [:named_table, :public, :set])
    :ets.new(@log_queue, [:named_table, :public, :ordered_set])

    Process.flag(:trap_exit, true)

    state = %{
      api_key: Application.get_env(:statsig, :api_key, nil),
      last_sync: 0,
      events: [],
      prefix: server,
      flush_interval: Keyword.get(opts, :flush_interval, @flush_interval),
      reload_interval: Keyword.get(opts, :reload_interval, @reload_interval),
      reload_timer: nil,
      flush_timer: nil
    }
    {:ok, state}
  end

  # TODO - PID should move to be the first argument
  def check_gate(user, gate)
  def check_gate(nil, _gate), do: {:error, :no_user}

  def check_gate(user, gate) do
    user = Utils.get_user_with_env(user, get_tier())

    result = Statsig.Evaluator.eval(user, gate, :gate)
    log_exposures(user, result.exposures, :gate)

    case result do
      %{reason: :not_found} -> {:error, :not_found}
      _ -> {:ok, result.result}
    end
  end
  # Make a layer module
  # The layer module can take a layer struct and return a value
  # use atoms as keys

  def get_config(user, config)
  def get_config(nil, _config), do: {:error, :no_user}

  def get_config(user, config) do
    user = Utils.get_user_with_env(user, get_tier())
    result = Statsig.Evaluator.eval(user, config, :config)
    log_exposures(user, result.exposures, :config)

    # TODO - could probably hand back a Result struct
    case result do
      %{reason: :not_found} -> {:error, :not_found}
      # TODO - this be {:ok, result}
      _ -> %{rule_id: Map.get(result.rule, "id"), value: result.value}
    end
  end

  def get_experiment(user, exp), do: get_config(user, exp)
  def get_experiment(user, exp), do: get_config(user, exp)


  def log_event(event) do
    insert_log(event)
    :ok
  end

  defp insert_log(event) do
    timestamp = :os.system_time(:nanosecond)
    :ets.insert(@log_queue, {timestamp, event})
  end

  def log_event(user, event_name, value, metadata) do
    user = Utils.get_user_with_env(user, get_tier())
    event = %{
      "eventName" => event_name,
      "value" => value,
      "metadata" => metadata,
      "time" => :os.system_time(:millisecond),
      "user" => Utils.sanitize_user(user)
    }
    insert_log(event)
    :ok
  end


  def state(server \\ __MODULE__), do: GenServer.call(server, :state)

  def lookup(name, type) do
    @config_store
    |> :ets.lookup({name, type})
  end

  def all(type) do
    @config_store
    |> :ets.match({{:"$1", type}, :_})
    |> List.flatten()
  end

  # for debugging
  def handle_call(:state, _from, state), do: {:reply, state, state}

  def handle_call(:flush, _from, %{api_key: key} = state) do
    flush_events(key)
    {:reply, state, state}
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

    %{api_key: state_api_key, last_sync: time} = state
    api_key = state_api_key || Application.get_env(:statsig, :api_key)
    {:ok, last_sync} = reload_configs(api_key, time)

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
      |> Map.put(:reload_timer, reload_timer)
      |> Map.put(:flush_timer, flush_timer)

    {:noreply, updated_state}
  end

  defp handle_reload(state) do
    %{api_key: api_key, last_sync: time, reload_interval: reload_interval} = state
    case reload_configs(api_key, time) do
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
    flush_events(state.api_key)
    flush_timer = Process.send_after(self(), :flush, state.flush_interval)
    {:noreply, state |> Map.put(:flush_timer, flush_timer)}
  end

  def terminate(_reason, %{api_key: key, events: events}) do
    Logger.info("for now, do nothing on terminate")
  end

  defp get_tier() do
    Application.get_env(:statsig, :env_tier, nil)
  end


  defp current_time do
    DateTime.utc_now() |> DateTime.to_unix(:millisecond)
  end

  defp log_exposures(_user, [], _type), do: :ok

  defp log_exposures(user, [%{"gate" => c, "ruleID" => r} | secondary], :config) do
    primary = %{
      "config" => c,
      "ruleID" => r
    }

    event =
      base_event(user, secondary, :config)
      |> Map.put("metadata", primary)

    insert_log(event)
  end

  defp log_exposures(user, [primary | secondary], type) do
    event =
      base_event(user, secondary, type)
      |> Map.put("metadata", primary)

      insert_log(event)
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

  defp reload_configs(api_key, since) do
    Logger.info("reload_configs triggered")
    case api_client().download_config_specs(api_key, since) do
      {:ok, config} ->
        new_time = Map.get(config, "time", 0)
        Logger.info("new_time: #{inspect(new_time)}")
        Logger.info("since_time: #{inspect(since)}")

        if is_number(new_time) and new_time > since do
          config |> Map.get("feature_gates", []) |> save_configs(:gate)
          config |> Map.get("dynamic_configs", []) |> save_configs(:config)
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
  def shutdown(server \\ __MODULE__) do
    try do
      GenServer.call(server, :shutdown)
      :ets.delete_all_objects(@config_store)
      :ets.delete_all_objects(@log_queue)
    catch
      :exit, {:timeout, _} ->
        :ets.delete_all_objects(@config_store)
        :ets.delete_all_objects(@log_queue)
        Logger.warn("Statsig shutdown timed out")
        :ok
    end
  end

  defp flush_events(key) do
    case :ets.select(@log_queue, [{:_, [], [:'$_']}], 1000) do
      {[], :'$end_of_table'} ->
        []  # No events to process
      {events, continue} ->
        events = Enum.map(events, fn {_timestamp, event} -> event end)

        unsent = events
        |> Enum.chunk_every(500)
        |> Enum.reduce([], fn chunk, unsent ->
          {_result, failed} = api_client().push_logs(key, chunk)
          failed ++ unsent
        end)

        sent_events = events -- unsent
        Enum.each(sent_events, fn event ->
          case :ets.match_object(@log_queue, {:_, event}) do
            [{timestamp, _}] -> :ets.delete(@log_queue, timestamp)
            _ -> :ok  # Event not found, possibly already deleted
          end
        end)

        case continue do
          :'$end_of_table' -> unsent
          _ -> unsent ++ flush_events(key)
        end
    end
  end

  defp save_configs([], _, _), do: :ok

  defp save_configs([%{"name" => name} = head | tail], type) when is_binary(name) do
    :ets.insert(@config_store, {{name, type}, head})
    save_configs(tail, type)
  end

  # config has no name, so skip it
  defp save_configs([_head | tail], type), do: save_configs(tail, type)

  # should maybe accept this as part of initialization, too, so different pids can use different clients
  defp api_client, do: Application.get_env(:statsig, :api_client, Statsig.APIClient)
end
