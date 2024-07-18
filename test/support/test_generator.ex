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
            if StatsigEx.PressureTest.all_conditions_supported?(
                 unquote(name),
                 unquote(type),
                 :test
               ) do
              result =
                StatsigEx.Evaluator.eval(
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

              # spit out the test details on failures
              # if Enum.sort(unquote(Macro.escape(secondary))) != Enum.sort(cal_sec) do
              #   IO.inspect(
              #     {unquote(Macro.escape(user)), unquote(name), unquote(type),
              #      unquote(Macro.escape(secondary))}
              #   )
              # end

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
end
