defmodule Statsig.Evaluator do
  @unsupported ["ip_based"]

  alias Statsig.EvaluationResult
  defmodule Context do
    defstruct spec: %{}, server: nil
  end

  def eval(user, name, type) do
    Statsig.Configs.lookup(name, type)
    |> case do
      [{_key, spec}] ->
        eval_and_add_exposure(user, %Context{spec: spec}, name)

      _other ->
        eval_and_add_exposure(user, nil, name)
    end
  end

  defp eval_and_add_exposure(_user, nil, name),
    do: %EvaluationResult{
      result: false,
      rule: %{id: "Unrecognized"},
      reason: :not_found,
      exposures: [
        %{gate: name, gateValue: "false", ruleID: "Unrecognized", value: %{}}
      ]
    }

  # don't add an exposure for segments (which are represented as gates)
  defp eval_and_add_exposure(user, ctx, <<"segment:", _::binary>>) do
    result = do_eval(user, ctx)
    %EvaluationResult{result | exposures: result.exposures |> Enum.reverse() |> Enum.uniq()}
  end

  defp eval_and_add_exposure(user, ctx, name) do
    result = do_eval(user, ctx)

    exposures = [
      %{
        gate: name,
        gateValue: to_string(result.result),
        ruleID: Map.get(result.rule, "id"),
        configVersion: to_string(Map.get(ctx.spec, "version", ""))
      }
      | Enum.reverse(result.exposures)
    ]

    %EvaluationResult{result | exposures: Enum.uniq(exposures)}
  end

  defp do_eval(_user, %Context{spec: %{"enabled" => false, "defaultValue" => default}}),
    do: %EvaluationResult{value: default, rule: %{id: "disabled"}, reason: :disabled}

  defp do_eval(user, %Context{spec: %{"rules" => rules}} = ctx),
    do: eval_rules(user, rules, ctx, [])

  defp eval_rules(_user, [], %Context{spec: %{"defaultValue" => default}}, results) do
    Enum.reduce(
      results,
      %EvaluationResult{result: false, value: default, rule: %{id: "default"}, reason: :no_rule_match},
      fn r, final ->
        %EvaluationResult{final | exposures: r.exposures ++ final.exposures}
      end
    )
  end

  # only evaluate as many rules as we need to to find a matching one
  defp eval_rules(user, [rule | rest], ctx, acc) do
    case eval_one_rule(user, rule, ctx) do
      %EvaluationResult{result: true} = result ->
        final_result = eval_pass_percent(user, rule, ctx)

        Enum.reduce(
          acc,
          %EvaluationResult{
            result
            | result: final_result,
              value: Map.get(rule, "returnValue"),
              reason: :rule_match
          },
          fn r, final ->
            %EvaluationResult{final | exposures: r.exposures ++ final.exposures}
          end
        )

      result ->
        eval_rules(user, rest, ctx, [result | acc])
    end
  end

  defp eval_one_rule(user, %{"conditions" => conds} = rule, ctx) do
    results = eval_conditions(user, conds, rule, ctx)

    # all conditions must match, and we should only include the rule if all match
    result =
      Enum.reduce(results, %EvaluationResult{result: true, raw_result: true}, fn curr, acc ->
        %EvaluationResult{
          result: curr.result && acc.result,
          raw_result: curr.raw_result && acc.raw_result,
          value: acc.value || curr.value,
          exposures: curr.exposures ++ acc.exposures
        }
      end)

    if result.raw_result || result.result,
      do: %EvaluationResult{result | rule: rule},
      else: result
  end

  defp eval_conditions(user, conds, rule, ctx, acc \\ [])
  defp eval_conditions(_user, [], _rule, _ctx, acc), do: acc

  # public conditions are final, so short-circuit this and return
  # gotta figure out how to make these final when they happen via pass/fail_gate
  defp eval_conditions(
         _user,
         [%{"type" => "public"} | _rest],
         rule,
         _ctx,
         acc
       ),
       do: [
         %EvaluationResult{
           result: true,
           raw_result: true,
           value: Map.get(rule, "returnValue"),
           rule: rule
         }
         | acc
       ]

  defp eval_conditions(
         user,
         [%{"type" => "pass_gate", "targetValue" => gate} | rest],
         rule,
         ctx,
         acc
       ) do
    result =
      case eval(user, gate, :gate) do
        %{result: true} = result ->
          %EvaluationResult{
            result
            | value: Map.get(rule, "returnValue"),
              rule: rule
          }

        other ->
          other
      end

    eval_conditions(user, rest, rule, ctx, [result | acc])
  end

  defp eval_conditions(
         user,
         [%{"type" => "fail_gate", "targetValue" => gate} | rest],
         rule,
         ctx,
         acc
       ) do
    result = eval(user, gate, :gate)

    returned_rule =
      if result.result,
        do: %{},
        else: rule

    result = %EvaluationResult{
      result
      | result: !result.result,
        raw_result: !result.raw_result,
        value: Map.get(rule, "returnValue"),
        rule: returned_rule
    }

    eval_conditions(user, rest, rule, ctx, [result | acc])
  end

  # ip_based compares are unsupported for now
  defp eval_conditions(user, [%{"type" => type} | rest], rule, ctx, acc)
       when type in @unsupported do
    IO.puts("unsupported type: #{type}")
    # not sure why raw_result is true here, but that's what the erlang client does...?
    eval_conditions(user, rest, rule, ctx, [%EvaluationResult{result: false, raw_result: true} | acc])
  end

  defp eval_conditions(
         user,
         [%{"targetValue" => target, "operator" => op} = c | rest],
         rule,
         ctx,
         acc
       ) do
    val = extract_value_to_compare(user, c)

    result =
      case compare(val, target, op) do
        # is there a reason we don't throw an exposure in here right now...?
        # should an exposure be logged any time we match a condition instead of only when we make it through the entire gate?
        true ->
          %EvaluationResult{result: true, raw_result: true, value: Map.get(rule, "returnValue"), rule: rule}

        r ->
          %EvaluationResult{result: r, raw_result: false, value: Map.get(rule, "returnValue"), rule: rule}
      end

    eval_conditions(user, rest, rule, ctx, [result | acc])
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

  defp extract_value_to_compare(user, %{"type" => "ua_based", "field" => field}) do
    case get_user_field(user, field) do
      nil ->
        ua = get_user_field(user, "userAgent") |> to_string() |> UAParser.parse()

        case field do
          os when os in ["os_name", "osname"] -> ua.os.family
          v when v in ["os_version", "osversion"] -> to_string(ua.os.version)
          bn when bn in ["browser_name", "browsername"] -> ua.family
          bv when bv in ["browser_version", "browserversion"] -> to_string(ua.version)
          _ -> nil
        end
        |> case do
          "" -> nil
          result -> result
        end

      val ->
        val
    end
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

  defp eval_pass_percent(_user, %{"passPercentage" => 100}, _ctx), do: true
  defp eval_pass_percent(_user, %{"passPercentage" => 0}, _ctx), do: false

  defp eval_pass_percent(user, %{"passPercentage" => perc, "idType" => prop} = rule, %Context{
         spec: spec
       }) do
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

  # make sure "any" is comparing a list
  defp compare(val, target, "any") when not is_list(target), do: compare(val, [target], "any")

  defp compare(val, target, "any") do
    s_val = to_string(val) |> String.downcase()
    Enum.any?(target, fn t -> val == t || s_val == t end)
  end

  defp compare(val, target, "any_case_sensitive") do
    s_val = to_string(val)
    Enum.any?(target, fn t -> val == t || s_val == t end)
  end

  # basically the opposite of "any"
  defp compare(val, target, "none"),
    do: !compare(val, target, "any")

  defp compare(val, target, "none_case_sensitive"),
    do: !compare(val, target, "any_case_sensitive")

  defp compare(val, target, "str_starts_with_any") do
    Enum.any?(target, fn t -> String.starts_with?(val, t) end)
  end

  defp compare(val, target, "str_ends_with_any") do
    Enum.any?(target, fn t -> String.ends_with?(val, t) end)
  end

  # should the target be a list?
  defp compare(val, target, "str_contains_any") do
    Enum.any?(target, fn t -> String.contains?(to_string(val), t) end)
  end

  defp compare(val, target, "str_contains_none"), do: !compare(val, target, "str_contains_any")

  # what should we do with nil values here?
  defp compare(val, target, "str_matches") do
    # make sure the regex can compile
    case Regex.compile(target) do
      {:ok, r} ->
        Regex.match?(r, to_string(val))

      _ ->
        false
    end
  end

  defp compare(val, target, "eq"), do: val == target
  defp compare(val, target, "neq"), do: val != target

  # all below comparisons are ~numeric, and should return false if either value is nil
  defp compare(val, target, _) when is_nil(val) or is_nil(target), do: false

  defp compare(val, target, "on") do
    {:ok, vd} = DateTime.from_unix(val, :millisecond)
    {:ok, td} = DateTime.from_unix(target, :millisecond)
    vd.year == td.year && vd.month == td.month && vd.day == td.day
  end

  # we probably need to do some type checking here, so we don't compare values of different types
  defp compare(val, target, "after"), do: val > target
  defp compare(val, target, "before"), do: val < target

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
        # fallback to parsing manually
        {vp, tp} = parse_versions_to_compare(val, target)
        compare_version_lists(vp, tp, type)
    end
  end

  defp compare(_, _, _op), do: false

  defp parse_versions_to_compare(a, b) do
    a = simple_version_parse(a)
    b = simple_version_parse(b)
    pad_len = max(length(a), length(b))
    {pad(a, pad_len - length(a)), pad(b, pad_len - length(b))}
  end

  defp simple_version_parse(v) do
    try do
      # drop -beta / -alpha versions, for now
      v |> String.split("-") |> hd |> String.split(".") |> Enum.map(&String.to_integer/1)
    rescue
      # because there can be versions that aren't numbers...?
      ArgumentError -> [v]
    end
  end

  defp pad(v, 0), do: v

  defp pad(v, len) do
    pad(v ++ [0], len - 1)
  end

  defp compare_simple_versions([], []), do: :eq

  defp compare_simple_versions([a | _], [b | _])
       when not is_integer(a) or not is_integer(b),
       do: false

  defp compare_simple_versions([a | ra], [b | rb]) do
    cond do
      a == b -> compare_simple_versions(ra, rb)
      a < b -> :lt
      a > b -> :gt
    end
  end

  defp compare_version_lists(val, target, "gt"), do: compare_simple_versions(val, target) == :gt
  defp compare_version_lists(val, target, "lt"), do: compare_simple_versions(val, target) == :lt
  defp compare_version_lists(val, target, "eq"), do: compare_simple_versions(val, target) == :eq
  defp compare_version_lists(val, target, "neq"), do: compare_simple_versions(val, target) != :eq

  defp compare_version_lists(val, target, "gte"),
    do: Enum.member?([:gt, :eq], compare_simple_versions(val, target))

  defp compare_version_lists(val, target, "lte"),
    do: Enum.member?([:lt, :eq], compare_simple_versions(val, target))

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
