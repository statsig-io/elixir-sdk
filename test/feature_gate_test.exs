defmodule Statsig.FeatureGateTest do
  use ExUnit.Case

  test "missing gate returns {:error, :not_found}" do
    assert {:error, :not_found} == Statsig.check_gate(%{}, "lkajsodin", :test)
  end
end
