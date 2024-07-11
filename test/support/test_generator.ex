defmodule StatsigEx.TestGenerator do
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
            result =
              StatsigEx.Evaluator.eval(
                unquote(Macro.escape(user)),
                unquote(name),
                unquote(type)
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
      end)
      |> Enum.filter(fn a -> a end)
      |> Enum.each(fn test_case ->
        Code.eval_quoted(test_case, [], __ENV__)
      end)
    end
  end
end
