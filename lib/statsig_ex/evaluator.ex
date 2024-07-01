defmodule StatsigEx.Evaluator do
  # here's what I sitll need to do:
  # * actually log exposures. These are logs of the gates / configs that are evaluated,
  #   so each gate / config eval should have one primary exposure and N secondary
  #   exposures (one for each pass/fail gate conditions encountered along the way).
  #   Exposures are returned from the evaluator, but I currently just drop them
  # * add env/tier ("statsigEnvironment") attribute to users (probably pulled in
  #   from application env)
  # * add metadata headers (sdk version, etc) to API calls
  # * rejigger the http/api client stuff to possibly be more configurable
  # * decide if I want to spin up a supervisor & the genserver automatically
  #   or just continue to have apps call start_link themselves

  # I think I just need to ignore this return value shape for now,
  # because it's confusing me and holding me back (it doesn't seem consistent anywhere)
  # {Rule, GateValue, JsonValue, ruleID/reason, Exposures}
  # {:ok, result, value, exposures}

  def find_and_eval(user, name, type) do
    case StatsigEx.lookup(name, type) do
      [{_key, spec}] ->
        do_eval(user, spec)

      _other ->
        {false, false, %{}, %{"id" => "Unrecognized"},
         [
           %{"gate" => name, "gateValue" => to_string(false), "ruleID" => "Unrecognized"}
         ]}
    end
  end

  # erlang client doesn't log an exposure for disabled flags, so neither will I
  defp do_eval(_user, %{"enabled" => false, "defaultValue" => default}),
    do: {false, false, default, %{}, []}

  defp do_eval(user, %{"rules" => rules} = spec), do: eval_rules(user, rules, spec, [])

  defp eval_rules(_user, [], %{"defaultValue" => default, "name" => name}, results) do
    # combine all the exposures and calculate result
    # only one rule needs to pass
    Enum.reduce(results, {false, true, nil, %{}, []}, fn {result, raw, value, rule, exposures},
                                                         {running_result, running_raw,
                                                          running_value, running_rule, acc} ->
      r =
        case Map.keys(running_rule) do
          [] -> rule
          _ -> running_rule
        end

      {result || running_result, running_raw && raw, running_value || value, r, exposures ++ acc}
    end)
    |> case do
      # in this case, we apparently want to list the rule_id as "default",
      # because we are falling back to the default
      # (at least, that's what the erlang client does :shrug:)
      # only add an exposure if there isn't already one, I guess?
      {false, _raw, _val, _rule, []} ->
        # do we always log the default exposure?
        # so...should this be true?
        {false, true, default, %{"id" => "default"},
         [
           %{
             "gate" => name,
             "gateValue" => to_string(false),
             "ruleID" => "default"
           }
         ]}

      {false, _raw, _val, _rule, exp} ->
        {false, true, default, %{"id" => "default"}, exp}

      pass ->
        pass
    end
  end

  defp eval_rules(user, [%{"id" => id} = rule | rest], %{"name" => name} = spec, acc) do
    # eval rules, and then
    eval_one_rule(user, rule, spec)
    |> case do
      # once we find a passing rule, we bail
      {true, raw, _val, r, exp} ->
        # I guess we should log an exposure, right?
        final_result = eval_pass_percent(user, rule, spec)

        eval_rules(user, [], spec, [
          {final_result, raw, Map.get(rule, "returnValue"), r,
           [
             %{
               "gate" => name,
               "ruleID" => id,
               # not sure if this should be raw or just true?
               "gateValue" => to_string(final_result)
             }
             | exp
           ]}
          | acc
        ])

      result ->
        eval_rules(user, rest, spec, [result | acc])
    end
  end

  defp eval_one_rule(user, %{"conditions" => conds, "id" => id} = rule, spec) do
    results = eval_conditions(user, conds, rule, spec)

    # as soon as we match a condition, we bail
    Enum.reduce(results, {true, true, nil, %{}, []}, fn {result, raw_result, value, rule, exp},
                                                        {running_result, running_raw_result,
                                                         running_value, running_rule, acc} ->
      r =
        case Map.keys(running_rule) do
          [] -> rule
          _ -> running_rule
        end

      {result && running_result, raw_result && running_raw_result, running_value || value, r,
       exp ++ acc}
    end)
  end

  defp eval_conditions(user, conds, rule, spec, acc \\ [])
  defp eval_conditions(_user, [], _rule, _spec, acc), do: acc
  # public conditions are final, so short-circuit this and return
  defp eval_conditions(_user, [%{"type" => "public"} | _rest], rule, _spec, acc),
    do: [
      # should I be calculating pass percentage on conditions...or just the rule level?
      # {eval_pass_percent(user, rule, spec), true, Map.get(rule, "returnValue"), rule, []} | acc
      {true, true, Map.get(rule, "returnValue"), rule, []} | acc
    ]

  defp eval_conditions(
         user,
         [%{"type" => "pass_gate", "targetValue" => gate} | rest],
         rule,
         spec,
         acc
       ) do
    result =
      case find_and_eval(user, gate, :gate) do
        # I don't think I care about the rule returned below, do I? it should be in the exposure
        # OR, should the rule be the final rule that matched...?
        # also, should the return value be from this rule or the passed rule...?
        {true, _raw, _val, _rule, exp} ->
          # {eval_pass_percent(user, rule, spec), true, Map.get(rule, "returnValue"), rule, exp}
          {true, true, Map.get(rule, "returnValue"), rule, exp}

        other ->
          other
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
      case find_and_eval(user, gate, :gate) do
        # false is a pass, since this is a FAIL gate check
        {false, _raw, _value, _rule, exp} ->
          # {eval_pass_percent(user, rule, spec), true, Map.get(rule, "returnValue"), rule, exp}
          {true, true, Map.get(rule, "returnValue"), rule, exp}

        # from which spec do we pull the default value...?
        {true, _raw, _value, _rule, exp} ->
          {false, false, Map.get(rule, "returnValue"), rule, exp}
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
        # is there a reason we don't throw an exposure in here right now...?
        # should an exposure be logged any time we match a condition instead of only when we make it through the entire gate?
        true ->
          # {eval_pass_percent(user, rule, spec), true, Map.get(rule, "returnValue"), rule, []}
          {true, true, Map.get(rule, "returnValue"), rule, []}

        r ->
          {r, false, Map.get(rule, "returnValue"), rule, []}
      end

    eval_conditions(user, rest, rule, spec, [result | acc])
  end

  defp extract_value_to_compare(user, %{"type" => "user_field", "field" => field}),
    do: get_user_field(user, field)

  defp extract_value_to_compare(user, %{"type" => "environment_field", "field" => field}),
    do: get_env_field(user, field)

  defp extract_value_to_compare(_user, %{"type" => "current_time"}),
    do: DateTime.utc_now() |> DateTime.to_unix(:millisecond)

  defp extract_value_to_compare(user, %{"type" => "unit_id", "idType" => id_type}) do
    get_user_id(user, id_type)
  end

  defp extract_value_to_compare(user, %{
         "type" => "user_bucket",
         "additionalValues" => %{"salt" => salt},
         "idType" => id_type
       }) do
    id = get_user_id(user, id_type)
    hash = user_hash("#{salt}.#{id}")
    rem(hash, 1_000)
  end

  defp eval_pass_percent(_user, %{"passPercentage" => 100}, _spec), do: true
  defp eval_pass_percent(_user, %{"passPercentage" => 0}, _spec), do: false

  defp eval_pass_percent(user, %{"passPercentage" => perc, "idType" => prop} = rule, spec) do
    spec_salt = Map.get(spec, "salt", Map.get(spec, "id", ""))
    rule_salt = Map.get(rule, "salt", Map.get(rule, "id", ""))
    id = get_user_id(user, prop)
    hash = user_hash("#{spec_salt}.#{rule_salt}.#{id}")
    rem(hash, 10_000) < perc * 100
  end

  # for none* conditions, if either is nil, return true
  defp compare(val, target, op)
       when op in ["none", "none_case_sensitive", "str_contains_none"] and
              (is_nil(val) or is_nil(target)) do
    true
  end

  # for everything else, return false
  defp compare(val, target, _) when is_nil(val) or is_nil(target), do: false

  # make sure "any" is comparing a list
  defp compare(val, target, "any") when not is_list(target), do: compare(val, [target], "any")

  defp compare(val, target, op) when op in ["any", "any_case_sensitive"],
    do: Enum.any?(target, fn t -> val == t end)

  # basically the opposite of "any"
  defp compare(val, target, op) when op in ["none", "none_case_sensitive"],
    do: !compare(val, target, "any")

  defp compare(val, target, "str_starts_with_any") do
    Enum.any?(target, fn t -> String.starts_with?(val, t) end)
  end

  defp compare(val, target, "str_ends_with_any") do
    Enum.any?(target, fn t -> String.ends_with?(val, t) end)
  end

  defp compare(val, target, "str_contains_any") do
    Enum.any?(target, fn t -> String.contains?(val, t) end)
  end

  defp compare(val, target, "str_contains_none"), do: !compare(val, target, "str_contains_any")

  defp compare(val, target, "str_matches") do
    # make sure the regex can compile
    case Regex.compile(target) do
      {:ok, r} ->
        Regex.match?(r, val)

      _ ->
        false
    end
  end

  defp compare(val, target, "on") do
    {:ok, vd} = DateTime.from_unix(val, :millisecond)
    {:ok, td} = DateTime.from_unix(target, :millisecond)
    vd.year == td.year && vd.month == td.month && vd.day == td.day
  end

  # we probably need to do some type checking here, so we don't compare values of different types
  defp compare(val, target, "after"), do: val > target
  defp compare(val, target, "before"), do: val < target

  defp compare(val, target, "eq"), do: val == target
  defp compare(val, target, "neq"), do: val != target
  defp compare(val, target, "gt"), do: val > target
  defp compare(val, target, "lt"), do: val < target
  defp compare(val, target, "lte"), do: val <= target
  defp compare(val, target, "gte"), do: val >= target

  defp compare(val, target, <<"version_", type::binary>>) do
    # we need to manually parse versions first to avoid raising Version.InvalidVersionError
    # we might consider padding as needed to make version strings all the right length
    case [Version.parse(val), Version.parse(target)] do
      [{:ok, v}, {:ok, t}] ->
        compare_versions(v, t, type)

      _ ->
        IO.puts("invalid version")
        false
    end
  end

  defp compare(_, _, op) do
    # IO.inspect(op, label: :unsupported_compare)
    false
  end

  defp compare_versions(val, target, "gt"), do: Version.compare(val, target) == :gt
  defp compare_versions(val, target, "lt"), do: Version.compare(val, target) == :lt
  defp compare_versions(val, target, "eq"), do: Version.compare(val, target) == :eq
  defp compare_versions(val, target, "neq"), do: Version.compare(val, target) != :eq

  defp compare_versions(val, target, "gte"),
    do: Enum.member?([:gt, :eq], Version.compare(val, target))

  defp compare_versions(val, target, "lte"),
    do: Enum.member?([:lt, :eq], Version.compare(val, target))

  defp user_hash(s) do
    <<hash::size(64), _rest::binary>> = :crypto.hash(:sha256, s)
    hash
  end

  defp get_user_id(user, "userID"), do: try_get_with_lower(user, "userID") |> to_string()

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
