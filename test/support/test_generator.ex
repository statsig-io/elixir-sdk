defmodule StatsigEx.TestGenerator do
  defmacro generate_tests(configs) do
    quote do
      Enum.flat_map(unquote(configs), fn %{
                                           "user" => user,
                                           "feature_gates_v2" => gates,
                                           "dynamic_configs" => d_configs
                                         } ->
        Enum.map(gates, fn {name, %{"value" => expected, "secondary_exposures" => sec}} ->
          quote do
            test(
              unquote(
                "gate #{name} for #{Map.get(user, "userID")} | #{
                  :crypto.strong_rand_bytes(8) |> Base.encode64()
                }"
              )
            ) do
              result =
                StatsigEx.Evaluator.eval(
                  unquote(Macro.escape(user)),
                  unquote(Macro.escape(name)),
                  :gate
                )

              [_ | cal_sec] = result.exposures
              assert unquote(Macro.escape(expected)) == result.result
              assert Enum.sort(unquote(Macro.escape(sec))) == Enum.sort(cal_sec)
            end
          end
        end) ++
          Enum.map(d_configs, fn {name, %{"value" => expected, "secondary_exposures" => sec}} ->
            quote do
              # ideally I'd skip some of these dynamically based on what checks we support
              # @tag skip: ...
              test(
                unquote(
                  "dynamic config #{name} for #{Map.get(user, "userID")} | #{
                    :crypto.strong_rand_bytes(8) |> Base.encode64()
                  }"
                )
              ) do
                result =
                  StatsigEx.Evaluator.eval(
                    unquote(Macro.escape(user)),
                    unquote(Macro.escape(name)),
                    :config
                  )

                [_ | cal_sec] = result.exposures

                assert unquote(Macro.escape(expected)) == result.value

                assert Enum.sort(unquote(Macro.escape(sec))) == Enum.sort(cal_sec)
              end
            end
          end)
      end)
      |> Enum.each(fn test_case ->
        Code.eval_quoted(test_case, [], __ENV__)
      end)
    end
  end
end
