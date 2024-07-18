defmodule StatsigEx.FeatureGateTest do
  use ExUnit.Case

  test "missing gate returns {:error, :missing}" do
    assert {:error, :not_found} == StatsigEx.check_gate(%{}, "lkajsodin", :test)
  end
end
