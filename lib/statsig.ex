defmodule Statsig do
  alias Statsig.EvaluationResult
  alias Statsig.User

  defdelegate log_event(event), to: Statsig.Logging
  defdelegate flush(), to: Statsig.Logging

  def check_gate(user, gate) do
    user = Statsig.Utils.get_user_with_env(user)

    result = Statsig.Evaluator.eval(user, gate, :gate)
    log_exposures(user, result, :gate)

    case result do
      %{reason: :not_found} -> {:error, :not_found}
      _ -> {:ok, result.result}
    end
  end

  def get_config(user, config) do
    user = Statsig.Utils.get_user_with_env(user)
    result = Statsig.Evaluator.eval(user, config, :config)
    log_exposures(user, result, :config)

    case result do
      %{reason: :not_found} -> {:error, :not_found}
      _ -> {:ok, Statsig.DynamicConfig.new(
        config,
        result.value,
        Map.get(result.rule, "id"),
        Map.get(result.rule, "groupName"),
        Map.get(result.rule, "idType"),
        result.exposures
      )}
    end
  end

  def get_experiment(user, experiment) do
    get_config(user, experiment)
  end

  def log_event(%User{} = user, event_name, value, metadata) do
    user = Statsig.Utils.get_user_with_env(user)

    event = %{
      eventName: event_name,
      value: value,
      metadata: metadata,
      time: System.system_time(:millisecond),
      user: Statsig.Utils.sanitize_user(user)
    }

    log_event(event)
  end

  defp log_exposures(%User{} = user, %EvaluationResult{} = result, :config) do
    [exposure | secondary] = result.exposures

    primary = %{
      config: exposure.gate,
      ruleID: exposure.ruleID,
      rulePassed: exposure.gateValue,
    }
    |> Map.merge(if Map.get(exposure, :configVersion), do: %{configVersion: exposure.configVersion}, else: %{})

    event =
      base_event(user, secondary, :config)
      |> Map.put(:metadata, primary)

    log_event(event)
  end

  defp log_exposures(%User{} = user, %EvaluationResult{} = result, type) do
    [primary | secondary] = result.exposures

    event =
      base_event(user, secondary, type)
      |> Map.put(:metadata, primary)

    log_event(event)
  end

  defp base_event(%User{} = user, secondary, type) do
    user = Statsig.Utils.sanitize_user(user)

    %{
      eventName: "statsig::#{type}_exposure",
      secondaryExposures: secondary,
      time: System.system_time(:millisecond),
      user: user
    }
  end
end
