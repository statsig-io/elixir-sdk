defmodule Statsig.TestGenerator do
  @unsupported_conditions ["ip_based"]
  @unsupported_gates ["test_id_list", "test_not_in_id_list"]
  @unsupported_configs ["test_exp_50_50_with_targeting_v2"]

  defmacro generate_all_tests(configs) do
    quote do
      Enum.flat_map(unquote(configs), fn %{
                                           "user" => user,
                                           "feature_gates_v2" => gates,
                                           "dynamic_configs" => d_configs
                                         } ->
        Enum.map(gates, fn {name, spec} -> {:gate, user, name, spec} end) ++
          Enum.map(d_configs, fn {name, spec} -> {:config, user, name, spec} end)
      end)
      # |> Enum.take(10)
      |> Enum.map(fn {type, user, name,
                      %{"value" => expected, "secondary_exposures" => secondary}} ->
        quote do
          test(
            unquote(
              "#{type} #{name} for #{Map.get(user, "userID")} | #{
                :crypto.strong_rand_bytes(8) |> Base.encode64()
              }"
            )
          ) do
            # skip if it's not supported (need to eventually support these, though)
            if Statsig.TestGenerator.all_conditions_supported?(
                 unquote(name),
                 unquote(type),
                 :test
               ) do
              result =
                Statsig.Evaluator.eval(
                  unquote(Macro.escape(user)),
                  unquote(name),
                  unquote(type),
                  :test
                )

              case unquote(type) do
                :gate ->
                  assert unquote(Macro.escape(expected)) == result.result

                _ ->
                  assert unquote(Macro.escape(expected)) == result.value
              end

              [_ | cal_sec] = result.exposures

              assert Enum.sort(unquote(Macro.escape(secondary))) == Enum.sort(cal_sec)
            end
          end
        end
      end)
      |> Enum.filter(fn a -> a end)
      |> Enum.each(fn test_case ->
        Code.eval_quoted(test_case, [], __ENV__)
      end)
    end
  end

  def all_conditions_supported?(gate, :gate, _server)
    when gate in @unsupported_gates,
    do: false

  def all_conditions_supported?(config, :config, _server)
    when config in @unsupported_configs,
    do: false

  def all_conditions_supported?(gate, type, server) do
  case Statsig.lookup(gate, type, server) do
    [{_key, spec}] ->
      Enum.reduce(Map.get(spec, "rules"), true, fn %{"conditions" => c}, acc ->
        acc &&
          Enum.reduce(c, true, fn %{"type" => type}, c_acc ->
            c_acc && !Enum.any?(@unsupported_conditions, fn n -> n == type end)
          end)
      end)

    _ ->
      true
  end
  end
end
