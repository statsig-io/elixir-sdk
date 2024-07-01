defmodule StatsigEx.ExposureLoggingTest do
  use ExUnit.Case

  # digging a bit deeper to ensure exposure logging is as expected
  test "exposure logging on simple gate" do
    compare_logs(%{}, "public", :gate)
  end

  test "exposure logging on more complex gate" do
    compare_logs(%{"userID" => "123"}, "multiple_conditions_per_rule", :gate)
  end

  test "exposure logging on pass gate" do
    compare_logs(%{"userID" => "123"}, "pass-gate", :gate)
  end

  test "exposure logging on more complex, multi-rule gate" do
    compare_logs(%{"userID" => "lkjlk"}, "complex-gate", :gate)
  end

  test "exposure logging on non-existent gate" do
    compare_logs(%{"userID" => "123"}, "xxxxxxxxx", :gate)
  end

  defp compare_logs(user, id, type) do
    # flush both
    :statsig.flush_sync()
    StatsigEx.flush()

    check(user, id, type)
    [{_, erl_logs} | _rest] = GenServer.call(:statsig_server, {:state})
    %{events: ex_logs} = StatsigEx.state()

    # the time is never gonna match, but _everything_ else should
    erl = Enum.map(erl_logs, &Map.delete(&1, "time"))
    ex = Enum.map(ex_logs, &Map.delete(&1, "time"))

    assert ex == erl
  end

  defp check(user, id, :gate) do
    StatsigEx.check_gate(user, id)
    :statsig.check_gate(user, id)
  end

  defp check(user, id, :config) do
    StatsigEx.get_config(user, id)
    :statsig.get_config(user, id)
  end
end
