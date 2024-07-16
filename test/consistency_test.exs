defmodule StatsigEx.ConsistencyTest do
  use ExUnit.Case
  import StatsigEx.TestGenerator
  import StatsigEx.PressureTest
  alias StatsigEx.Evaluator

  "test/data/rulesets_e2e_expected_results.json"
  |> Path.expand()
  |> File.read!()
  |> Jason.decode!()
  |> Map.get("data")
  |> generate_all_tests()

  @tag :skip
  test "one test" do
    result =
      StatsigEx.Evaluator.eval(
        %{
          "appVersion" => "1.3",
          "ip" => "1.0.0.0",
          "locale" => "en_US",
          "statsigEnvironment" => %{"tier" => "DEVELOPMENT"},
          "userAgent" =>
            "Mozilla/5.0 (iPhone; CPU iPhone OS 10_3_1 like Mac OS X) AppleWebKit/603.1.30 (KHTML, like Gecko) Version/10.0 Mobile/14E304 Safari/602.1",
          "userID" => "123"
        },
        "test_gate_with_targeting_gate",
        :gate
      )

    secondary = [
      %{
        "gate" => "global_holdout",
        "gateValue" => "false",
        "ruleID" => "3QoA4ncNdVGBaMt3N1KYjz:0.50:1"
      },
      %{
        "gate" => "test_targeting_gate_with_no_rules",
        "gateValue" => "false",
        "ruleID" => "default"
      }
    ]

    [_ | sec] = result.exposures
    assert Enum.sort(secondary) == Enum.sort(sec)
  end
end
