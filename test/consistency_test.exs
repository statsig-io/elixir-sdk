defmodule StatsigEx.ConsistencyTest do
  use ExUnit.Case
  alias StatsigEx.Evaluator

  test "everything" do
    # load the data
    {:ok, data} =
      "test/data/rulesets_e2e_expected_results.json"
      |> Path.expand()
      |> File.read!()
      |> Jason.decode()

    data = Map.get(data, "data")
    IO.puts(length(data))

    Enum.each(data, &run_tests/1)
  end

  test "one gate" do
    refute Evaluator.eval(
             %{
               "appVersion" => "1.2.3-alpha",
               "ip" => "1.0.0.0",
               "locale" => "en_US",
               "userAgent" =>
                 "Mozilla/5.0 (iPhone; CPU iPhone OS 10_3_1 like Mac OS X) AppleWebKit/603.1.30 (KHTML, like Gecko) Version/10.0 Mobile/14E304 Safari/602.1",
               "userID" => "123"
             },
             "test_numeric_lte_gte",
             :gate
           )
  end

  defp run_tests(%{
         "user" => user,
         "feature_gates_v2" => gates,
         "dynamic_configs" => configs
       }) do
    test_gates(user, gates)
  end

  def test_gates(user, gates) when is_map(gates) do
    gate_list = Enum.map(gates, fn {_key, config} -> config end)
    test_supported_gates(user, gate_list, {0, []})
  end

  def test_supported_gates(_user, [], {c, results}), do: {c, results}

  def test_supported_gates(user, [%{"name" => gate, "value" => expected} | rest], {c, results}) do
    if all_conditions_supported?(gate, :gate) do
      {r, _, _, _rule, _exposures} = Evaluator.eval(user, gate, :gate)

      assert r == expected,
             "failed for #{gate}(#{c + 1}) | #{r} :: #{expected} | #{inspect(user)}"

      test_supported_gates(user, rest, {c + 1, [r == expected | results]})
    else
      test_supported_gates(user, rest, {c, results})
    end
  end

  defp all_conditions_supported?(gate, type) do
    case StatsigEx.lookup(gate, type) do
      [{_key, spec}] ->
        IO.inspect(spec)

        Enum.reduce(Map.get(spec, "rules"), true, fn %{"conditions" => c}, acc ->
          acc &&
            Enum.reduce(c, true, fn %{"type" => type}, c_acc ->
              c_acc && !Enum.any?(["ip_based"], fn n -> n == type end)
            end)
        end)

      _ ->
        false
    end
  end
end
