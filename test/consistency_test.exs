defmodule StatsigEx.ConsistencyTest do
  use ExUnit.Case
  import StatsigEx.TestGenerator
  alias StatsigEx.Evaluator

  def filter_unsupported([], acc), do: acc

  def filter_unsupported([suite | rest], acc) do
    filtered_gates =
      Enum.filter(Map.get(suite, "feature_gates_v2"), fn gate ->
        !all_conditions_supported?(gate, :gate)
      end)

    filter_unsupported([Map.put(suite, "feature_gates_v2", filtered_gates) | acc])
  end

  "test/data/rulesets_e2e_expected_results.json"
  |> Path.expand()
  |> File.read!()
  |> Jason.decode!()
  |> Map.get("data")
  |> generate_tests()

  defp run_tests(
         %{
           "user" => user,
           "feature_gates_v2" => gates,
           "dynamic_configs" => configs
         },
         suite
       ) do
    test_gates(user, gates, suite)
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
  defp all_conditions_supported?(gate, :gate)
       when gate in ["test_not_in_id_list", "test_id_list"],
       do: false

  defp all_conditions_supported?(gate, type) do
    case StatsigEx.lookup(gate, type) do
      [{_key, spec}] ->
        # IO.inspect(spec, label: Map.get(spec, "name"))

        Enum.reduce(Map.get(spec, "rules"), true, fn %{"conditions" => c}, acc ->
          acc &&
            Enum.reduce(c, true, fn %{"type" => type, "operator" => op}, c_acc ->
              c_acc && !Enum.any?(["ip_based"], fn n -> n == type end)
            end)
        end)

      _ ->
        false
    end
  end
end
