defmodule StatsigEx.TestGenerator do
  defmacro generate_tests(configs) do
    quote do
      Enum.flat_map(unquote(configs), fn %{
                                           "user" => user,
                                           "feature_gates_v2" => gates,
                                           "dynamic_configs" => d_configs
                                         } ->
        Enum.map(gates, fn {name, %{"value" => expected}} ->
          quote do
            test(
              unquote(
                "gate #{name} for #{Map.get(user, "userID")} | #{
                  :crypto.strong_rand_bytes(8) |> Base.encode64()
                }"
              )
            ) do
              assert StatsigEx.Evaluator.eval(
                       unquote(Macro.escape(user)),
                       unquote(Macro.escape(name)),
                       :gate
                     ).result ==
                       unquote(expected)
            end
          end
        end) ++
          Enum.map(d_configs, fn {name, %{"value" => expected}} ->
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
                assert StatsigEx.Evaluator.eval(
                         unquote(Macro.escape(user)),
                         unquote(Macro.escape(name)),
                         :config
                       ).value ==
                         unquote(Macro.escape(expected))
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
