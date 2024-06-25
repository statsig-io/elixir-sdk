defmodule StatsigEx.Evaluator do
  @example %{
    "company_id" => "26adq53NuHkqUWjKEHQj9c",
    "diagnostics" => %{
      "api_call" => 100,
      "dcs" => 1000,
      "download_config_specs" => 1000,
      "get_id_list" => 100,
      "get_id_list_sources" => 100,
      "idlist" => 100,
      "initialize" => 10000,
      "log" => 100,
      "log_event" => 100
    },
    "dynamic_configs" => [],
    "feature_gates" => [
      %{
        "defaultValue" => false,
        "enabled" => true,
        "entity" => "feature_gate",
        "idType" => "userID",
        "isDeviceBased" => false,
        "name" => "phil-test",
        "rules" => [
          %{
            "conditions" => [
              %{
                "additionalValues" => %{},
                "field" => "userID",
                "idType" => "userID",
                "isDeviceBased" => false,
                "operator" => "any",
                "targetValue" => ["phil", "testing-with-junk"],
                "type" => "user_field"
              }
            ],
            "id" => "hNkxBZcDzHZN75DmZnwm1",
            "idType" => "userID",
            "isDeviceBased" => false,
            "name" => "hNkxBZcDzHZN75DmZnwm1",
            "passPercentage" => 100,
            "returnValue" => true,
            "salt" => "5d546ef7-341b-489b-bdb4-2534aee2d71f"
          },
          %{
            "conditions" => [
              %{
                "additionalValues" => %{},
                "field" => nil,
                "idType" => "userID",
                "isDeviceBased" => false,
                "operator" => nil,
                "targetValue" => nil,
                "type" => "public"
              }
            ],
            "id" => "3BnAGFoSOhh7gpGCjtkdWU",
            "idType" => "userID",
            "isDeviceBased" => false,
            "name" => "3BnAGFoSOhh7gpGCjtkdWU",
            "passPercentage" => 10,
            "returnValue" => true,
            "salt" => "a7de96a1-2534-4120-91d6-4538284035d6"
          }
        ],
        "salt" => "8ec7d4a1-9526-45ec-9424-3238f91990dd",
        "type" => "feature_gate"
      }
    ],
    "has_updates" => true,
    "id_lists" => %{},
    "layer_configs" => [],
    "layers" => %{},
    "sdk_configs" => %{"event_queue_size" => 500},
    "sdk_flags" => %{},
    "time" => 1719355460869
  }


  # {:ok, rule(?), result, value, reason, exposures}
  def eval(user, name, type) do
    case :ets.lookup(Statsig.ets_name(), {name, type}) do
      [_key, spec] ->
        # evaluate the rules...?
        do_eval(user, spec)

      _ ->
        {:error, false, :not_found}
    end
  end

  defp do_eval(user, spec,  exposures \\ [])

  defp do_eval(
         user,
         %{"enabled" => true, "rules" => rules, "defaultValue" => default},
         exposures
       ),
       do: eval_rules(user, default, rules, exposures)

  defp do_eval(user,  _disabled, exposures), do: {:ok, false, :disabled}

  defp eval_rules(user, result, [], exposures), do: {:ok, result}

  defp eval_rules(user, default, [rule | rest], exposures) do
    conds = Map.get(rule, "conditions", [])
    results = Enum.map(conds, fn c -> eval_condition(user, c) end)
  end

  defp eval_condition(user, condition) do
    # case get_evaluation_value(user, condition) do
    #   {_, false, value, exposures} -> {get_evaluation_comparison(condition, value), exposures}
    #   {result, _, _, exposures} -> {result, exposures}
    # end
  end

  defp get_evaluation_value(_, %{"type" => "public"}), do: {true, true, nil, []}

  defp get_evaluation_value(_, %{"type" => "current_time"}),
    do: {false, false, DateTime.to_unix(DateTime.utc_now()), []}

  defp get_evaluation_value(user, %{"type" => "pass_gate", "targetValue" => target}) do
    # alias for another gate, I guess?
    eval(user, target, :gate)
  end
end
