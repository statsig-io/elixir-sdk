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

  # @tag :skip
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

    [_ | sec] = result.exposures |> IO.inspect()
    # sec = result.exposures |> IO.inspect()

    assert Enum.sort(secondary) == Enum.sort(sec)
  end

  def test_gates(user, gates, suite) when is_map(gates) do
    gate_list = Enum.map(gates, fn {_key, config} -> config end)
    test_supported_gates(user, gate_list, {{suite, 0}, []})
  end

  def test_supported_gates(_user, [], results), do: results

  def test_supported_gates(
        user,
        [%{"name" => gate, "value" => expected} | rest],
        {{suite, test}, results}
      ) do
    if all_conditions_supported?(gate, :gate) do
      # IO.inspect(user)
      # IO.puts("")
      r = Evaluator.eval(user, gate, :gate)

      assert r.result == expected,
             "failed for #{gate}(#{suite}|#{test}) | r:#{r.result} :: e:#{expected} |\n #{
               inspect(user)
             } \n #{inspect(r)}"

      test_supported_gates(user, rest, {{suite, test + 1}, [r == expected | results]})
    else
      test_supported_gates(user, rest, {{suite, test}, results})
    end
  end

  # for now, just skip these, because we don't pull ID lists yet
end
