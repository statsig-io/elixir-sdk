defmodule StatsigEx.ExposureLoggingTest do
  use ExUnit.Case
  import StatsigEx.PressureTest
  alias StatsigEx.Evaluator

  # skip because the erlang client seems to not always get this right?
  @tag :skip
  test "primary exposure vs erlang in existing configs and gates" do
    data =
      "test/data/rulesets_e2e_expected_results.json"
      |> Path.expand()
      |> File.read!()
      |> Jason.decode!()
      |> Map.get("data")
      |> Enum.each(fn %{"user" => user, "dynamic_configs" => configs, "feature_gates_v2" => gates} ->
        Enum.each(configs, fn {name, _} ->
          if all_conditions_supported?(name, :config) do
            compare_primary_exposure(user, name, :config)
          end
        end)

        Enum.each(gates, fn {name, _} ->
          if all_conditions_supported?(name, :gate) do
            compare_primary_exposure(user, name, :gate)
          end
        end)
      end)
  end

  defp compare_primary_exposure(user, id, type) do
    flush()
    check(user, id, type)
    [{_, erl_logs} | _rest] = GenServer.call(:statsig_server, {:state})
    %{events: ex_logs} = StatsigEx.state()

    prune = fn logs ->
      logs
      |> Enum.map(fn log ->
        log
        |> Map.delete("time")
        |> Map.delete("secondaryExposures")
      end)
    end

    erl = prune.(erl_logs)
    ex = prune.(ex_logs)

    # if erl != ex, do: IO.inspect({user, id, type})
    # , "test: #{inspect(user)} :: #{id} :: #{type}"
    assert erl == ex
  end

  defp compare_logs(user, id, type) do
    flush()
    check(user, id, type)
    [{_, erl_logs} | _rest] = GenServer.call(:statsig_server, {:state})
    %{events: ex_logs} = StatsigEx.state()

    # the time is never gonna match, but _everything_ else should
    erl = Enum.map(erl_logs, &Map.delete(&1, "time"))
    ex = Enum.map(ex_logs, &Map.delete(&1, "time"))

    assert erl == ex
  end

  defp check(user, id, :gate) do
    StatsigEx.check_gate(user, id)
    :statsig.check_gate(user, id)
  end

  defp check(user, id, :config) do
    StatsigEx.get_config(user, id)
    :statsig.get_config(user, id)
  end

  defp flush do
    # flush both
    :statsig.flush_sync()
    StatsigEx.flush()
  end
end
