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

    Enum.reduce(data, 0, fn d, c ->
      run_tests(d, c)
      c + 1
    end)

    # Enum.each(data, &run_tests/1)
  end

  test "one gate" do
    # expect: false
    refute Evaluator.eval(
             %{
               "appVersion" => "1.3",
               "ip" => "1.0.0.0",
               "locale" => "en_US",
               "userAgent" =>
                 "Mozilla/5.0 (Windows NT 5.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/109.0.5414.87 ADG/11.0.4060 Safari/537.36",
               "userID" => "123"
             },
             "test_windows_7",
             :gate
           )
  end

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
      IO.inspect(user)
      IO.puts("")
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
        IO.inspect(spec, label: Map.get(spec, "name"))

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
