defmodule StatsigEx.EvaluatorTest do
  use ExUnit.Case
  alias StatsigEx.Evaluator

  # digging a bit deeper to ensure exposure logging is as expected
  test "exposure logging on simple gate" do
    assert normalize(Evaluator.find_and_eval(%{}, "public", :gate)) ==
             normalize(:evaluator.find_and_eval(%{}, "public", :feature_gate))
  end

  test "exposure logging on multiple conditions per rule" do
    assert normalize(Evaluator.find_and_eval(%{}, "multiple_conditions_per_rule", :gate)) ==
             normalize(
               :evaluator.find_and_eval(%{}, "multiple_conditions_per_rule", :feature_gate)
             )
  end

  # ex
  defp normalize({result, value, %{"id" => rule_id} = rule, exposures}) do
    {rule, result, value, rule_id, exposures}
  end

  # erl
  # defp normalize({rule, result, value, rule_id, expsosures})
  defp normalize(r), do: r
end

# gates:
# "public"
# "multiple_conditions_per_rule"
