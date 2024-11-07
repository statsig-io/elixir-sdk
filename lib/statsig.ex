defmodule Statsig do
  @type options :: %{
    api_key: String.t(),
    api_url: String.t() | nil,
    env_tier: String.t() | nil,
    reload_interval: integer() | nil,
    flush_interval: integer() | nil
  }

  def initialize(options) do
    # Initialize configs
    configs_result = Statsig.Configs.initialize(options)
    # Initialize logging
    logging_result = Statsig.Logging.initialize(options)

    case {configs_result, logging_result} do
      {:ok, :ok} ->
        :ok
      _ ->
        {:error, :initialization_failed}
    end
  end

  def check_gate(user, gate) do
    user = Statsig.Utils.get_user_with_env(user)

    result = Statsig.Evaluator.eval(user, gate, :gate)
    log_exposures(user, result.exposures, :gate)

    case result do
      %{reason: :not_found} -> {:ok, result.result}
      _ -> {:ok, result.result}
    end
  end

  def get_config(user, config) do
    user = Statsig.Utils.get_user_with_env(user)
    result = Statsig.Evaluator.eval(user, config, :config)
    log_exposures(user, result.exposures, :config)

    case result do
      %{reason: :not_found} -> {:error, :not_found}
      _ -> %{rule_id: Map.get(result.rule, "id"), value: result.value}
    end
  end

  def get_experiment(user, experiment) do
    get_config(user, experiment)
  end

  def log_event(event) do
    GenServer.cast(Statsig.Logging, {:log_event, event})
  end

  def log_event(user, event_name, value, metadata) do
    user = Statsig.Utils.get_user_with_env(user)
    event = %{
      "eventName" => event_name,
      "value" => value,
      "metadata" => metadata,
      "time" => :os.system_time(:millisecond),
      "user" => Statsig.Utils.sanitize_user(user)
    }
    GenServer.cast(Statsig.Logging, {:log_event, event})
  end

  def shutdown() do
    configs_result = Statsig.Configs.shutdown()
    logging_result = Statsig.Logging.shutdown()
  end

  defp log_exposures(user, [%{"gate" => c, "ruleID" => r} | secondary], :config) do
    primary = %{
      "config" => c,
      "ruleID" => r
    }

    event =
      base_event(user, secondary, :config)
      |> Map.put("metadata", primary)

      GenServer.cast(Statsig.Logging, {:log_event, event})
  end

  defp log_exposures(user, [primary | secondary], type) do
    event =
      base_event(user, secondary, type)
      |> Map.put("metadata", primary)

      GenServer.cast(Statsig.Logging, {:log_event, event})
  end

  defp base_event(user, secondary, type) do
    user = Statsig.Utils.sanitize_user(user)

    %{
      "eventName" => "statsig::#{type}_exposure",
      "secondaryExposures" => secondary,
      "time" => DateTime.utc_now() |> DateTime.to_unix(:millisecond),
      "user" => user
    }
  end

end
