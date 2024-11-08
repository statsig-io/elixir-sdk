defmodule Statsig do

  def check_gate(user, gate) do
    user = Statsig.Utils.get_user_with_env(user)

    result = Statsig.Evaluator.eval(user, gate, :gate)
    log_exposures(user, result.exposures, :gate)

    case result do
      %{reason: :not_found} -> {:error, :not_found}
      _ -> {:ok, result.result}
    end
  end

  def get_config(user, config) do
    user = Statsig.Utils.get_user_with_env(user)
    result = Statsig.Evaluator.eval(user, config, :config)
    log_exposures(user, result.exposures, :config)

    # TODO - could probably hand back a Result struct
    case result do
      %{reason: :not_found} -> {:error, :not_found}
      # TODO - this be {:ok, result}
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

  def flush() do
    logging_result = Statsig.Logging.flush()
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
