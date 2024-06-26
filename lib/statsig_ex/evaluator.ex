defmodule StatsigEx.Evaluator do
  # here's what we need to do:
  # 1. find the rule
  # 2. iterate through the conditions
  # 3. record exposures through each condition
  # 4. store eval result of each rule (should we bail early if a rule returns true? (possibly?))
  # 5. push exposures as logs at the end of it all
  # 6. return the tuple result

  # I think I just need to ignore this return value shape for now,
  # because it's confusing me and holding me back (it doesn't seem consistent anywhere)
  # {Rule, GateValue, JsonValue, ruleID/reason, Exposures}
  # {:ok, result, value, exposures}

  def find_and_eval(user, name, type) do
    case :ets.lookup(StatsigEx.ets_name(), {name, type}) do
      [{_key, spec}] ->
        do_eval(user, spec)

      _other ->
        # {:ok, false, :not_found}
        false
    end
  end

  defp do_eval(_user, %{"enabled" => false}), do: false
  defp do_eval(user, %{"rules" => rules} = spec), do: eval_rules(user, rules, spec, [])

  defp eval_rules(_user, [], _spec, acc), do: Enum.any?(acc)

  defp eval_rules(user, [rule | rest], spec, acc) do
    # eval rules, and then
    case eval_one_rule(user, rule, spec) do
      # once we find a passing rule, move on
      true ->
        eval_rules(user, [], spec, [eval_pass_percent(user, rule, spec) | acc])

      result ->
        eval_rules(user, rest, spec, [result | acc])
    end
  end

  defp eval_one_rule(user, %{"conditions" => conds} = rule, spec) do
    results = eval_conditions(user, conds, rule, spec)
    Enum.all?(results)
  end

  defp eval_conditions(user, conds, rule, spec, acc \\ [])
  defp eval_conditions(_user, [], _rule, _spec, acc), do: acc
  # public conditions are final, so short-circuit this and return
  defp eval_conditions(user, [%{"type" => "public"} | _rest], rule, spec, acc),
    do: [eval_pass_percent(user, rule, spec) | acc]

  defp eval_conditions(
         user,
         [%{"type" => "pass_gate", "targetValue" => gate} | rest],
         rule,
         spec,
         acc
       ) do
    result =
      case find_and_eval(user, gate, :gate) do
        true -> eval_pass_percent(user, rule, spec)
        _ -> false
      end

    eval_conditions(user, rest, rule, spec, [result | acc])
  end

  defp eval_conditions(
         user,
         [%{"type" => "fail_gate", "targetValue" => gate} | rest],
         rule,
         spec,
         acc
       ) do
    result =
      case not find_and_eval(user, gate, :gate) do
        true -> eval_pass_percent(user, rule, spec)
        _ -> false
      end

    eval_conditions(user, rest, rule, spec, [result | acc])
  end

  defp eval_conditions(
         user,
         [%{"targetValue" => target, "operator" => op} = c | rest],
         rule,
         spec,
         acc
       ) do
    val = extract_value_to_compare(user, c)

    result =
      case compare(val, target, op) do
        true -> eval_pass_percent(user, rule, spec)
        _ -> false
      end

    eval_conditions(user, rest, rule, spec, [result | acc])
  end

  defp extract_value_to_compare(user, %{"type" => "user_field", "field" => field}),
    do: get_user_field(user, field)

  defp extract_value_to_compare(user, %{"type" => "environment_field", "field" => field}),
    do: get_env_field(user, field)

  defp extract_value_to_compare(_user, %{"type" => "current_time"}),
    do: DateTime.utc_now() |> DateTime.to_unix(:millisecond)

  defp eval_pass_percent(_user, %{"passPercentage" => 100}, _spec), do: true
  defp eval_pass_percent(_user, %{"passPercentage" => 0}, _spec), do: false

  defp eval_pass_percent(user, %{"passPercentage" => perc, "idType" => prop} = rule, spec) do
    spec_salt = Map.get(spec, "salt", Map.get(spec, "id", ""))
    rule_salt = Map.get(rule, "salt", Map.get(rule, "id", ""))
    id = get_user_id(user, prop)
    hash = user_hash("#{spec_salt}.#{rule_salt}.#{id}")
    rem(hash, 10_000) < perc * 100
  end

  defp compare(val, target, "any") when is_list(target),
    do: Enum.any?(target, fn t -> val == t end)

  defp compare(val, target, "any"), do: compare(val, [target], "any")

  defp compare(val, target, "after"), do: val > target
  defp compare(val, target, "before"), do: val < target

  defp user_hash(s) do
    <<hash::size(64), _rest::binary>> = :crypto.hash(:sha256, s)
    hash
  end

  defp get_user_id(user, "userID" = prop), do: try_get_with_lower(user, prop) |> to_string()

  defp get_user_id(user, prop),
    do: try_get_with_lower(Map.get(user, "customIDs", %{}), prop) |> to_string()

  # this is kind of messy, but it should work for now
  defp get_user_field(user, prop) do
    case try_get_with_lower(user, prop) do
      nil -> try_get_with_lower(Map.get(user, "custom", %{}), prop)
      found -> found
    end
    |> case do
      nil -> try_get_with_lower(Map.get(user, "privateAttributes", %{}), prop)
      found -> found
    end
  end

  defp get_env_field(%{"statsigEnvironment" => env}, field),
    do: try_get_with_lower(env, field) |> to_string()

  defp get_env_field(_, _), do: nil

  defp try_get_with_lower(obj, prop) do
    lower = String.downcase(prop)

    case Map.get(obj, prop) do
      x when x == nil or x == [] or x == "" -> Map.get(obj, lower)
      x -> x
    end
  end
end
