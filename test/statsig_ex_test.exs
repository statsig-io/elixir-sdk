defmodule StatsigExTest do
  use ExUnit.Case
  import StatsigEx.PressureTest
  doctest StatsigEx

  test "non-existent flag returns false" do
    refute StatsigEx.check_gate(%{"userID" => "whatever"}, "doesnt-exist-anywhere")
  end

  test "disabled flag returns false" do
    refute StatsigEx.check_gate(%{"userID" => "anyone"}, "disabled")
  end

  describe "flag with 'Everyone' condition, 100% pass" do
    test "matches all" do
      assert StatsigEx.check_gate(%{"userID" => "phil"}, "public")
      assert StatsigEx.check_gate(%{"userID" => "other"}, "public")
    end
  end

  test "flag with 'Everyone' condition, 0% pass fails all" do
    refute StatsigEx.check_gate(%{"userID" => "phil"}, "public-0-perc")
    refute StatsigEx.check_gate(%{"userID" => "other"}, "public-0-perc")
  end

  test "flag with 'Everyone' condition, 99% pass passes" do
    assert StatsigEx.check_gate(%{"userID" => "phil"}, "public-99-perc")
  end

  test "flag with 'Everyone' condition, 1% pass fails" do
    refute StatsigEx.check_gate(%{"userID" => "phil"}, "public-1-perc")
  end

  describe "pass_gate flag" do
    test "that is 100% and proxied to gate that is 100% pass for everyone should pass" do
      assert StatsigEx.check_gate(%{"userID" => "phil"}, "pass-gate")
    end

    test "that is 0% pass and proxied to a gete that is 100% pass for everyone should fail" do
      refute StatsigEx.check_gate(%{"userID" => "phil"}, "pass-gate-0-perc")
    end
  end

  describe "fail_gate flag" do
    test "that is 100% and proxied to gate that is 0% pass for everyone should pass" do
      assert StatsigEx.check_gate(%{"userID" => "phil"}, "fail-gate-open")
    end

    test "that is 100% and proxied to gate that is 100% pass for everyone should fail" do
      refute StatsigEx.check_gate(%{"userID" => "phil"}, "fail-gate-closed")
    end
  end

  describe "user_field gate" do
    test "user ID is in list" do
      assert StatsigEx.check_gate(%{"userID" => "phil"}, "user-field-userid-is-in")
    end

    test "user ID is NOT in the list" do
      refute StatsigEx.check_gate(%{"userID" => "nope"}, "user-field-userid-is-in")
    end
  end

  describe "environment_field gate" do
    test "environment value is in list" do
      assert StatsigEx.check_gate(
               %{"userID" => "test", "statsigEnvironment" => %{"tier" => "production"}},
               "env-field-production-tier-is-in"
             )
    end
  end

  describe "current_time gate" do
    test "time is after 6/1/24" do
      assert StatsigEx.check_gate(%{}, "time-after-x")
    end
  end

  describe "segments" do
    test "simple conditional segment" do
      assert StatsigEx.check_gate(%{"userID" => "phil"}, "simple-segment")
    end
  end

  describe "customer ID gate" do
    test "is in list" do
      assert StatsigEx.check_gate(
               %{
                 "customIDs" => %{
                   "customerId" => "123"
                 },
                 "userID" => "any"
               },
               "customer-id-in-list"
             )
    end
  end

  describe "version compares" do
    test "greater than version works as expected" do
      assert StatsigEx.check_gate(%{"appVersion" => "1.1.1"}, "version-greater-than")
      refute StatsigEx.check_gate(%{"appVersion" => "0.9.0"}, "version-greater-than")
    end

    test "less than version works as expected" do
      refute StatsigEx.check_gate(%{"appVersion" => "1.8.2"}, "version-less-than")
      assert StatsigEx.check_gate(%{"appVersion" => "0.7.0-alpha"}, "version-less-than")
      assert StatsigEx.check_gate(%{"appVersion" => "0.6.9"}, "version-less-than")
    end
  end

  describe "vs. the erlang client" do
    test "non-existent gate" do
      {user, gate} = {%{"userID" => "whatever"}, "doesnt-exist-anywhere"}
      assert StatsigEx.check_gate(user, gate) == :statsig.check_gate(user, gate)
    end

    test "disabled flag" do
      {user, gate} = {%{"userID" => "anyone"}, "disabled"}
      assert StatsigEx.check_gate(user, gate) == :statsig.check_gate(user, gate)
    end

    test "segmentation of experiment is exactly the same" do
      gate = "basic-a-b"

      pressure_test_and_compare(:get_experiment, [gate])
    end
  end

  describe "gates" do
    test "multi-rule gate" do
      # pressure_test_and_compare(:check_gate, ["complex-gate"])
      user = %{"userID" => "abc"}
      # , "email" => "hello@nope.com"}

      assert StatsigEx.check_gate(user, "complex-gate") ==
               :statsig.check_gate(user, "complex-gate")
    end

    test "all existing flags" do
      Enum.each(StatsigEx.all(:gate), fn gate ->
        pressure_test_and_compare(:check_gate, [gate])
      end)
    end

    test "non-existent flags" do
      pressure_test_and_compare(:check_gate, ["non-existent"], 100)
    end
  end

  describe "dynamic configs" do
    test "all existing configs" do
      Enum.each(StatsigEx.all(:config), fn config ->
        pressure_test_and_compare(:get_config, [config])
      end)
    end

    test "non-existent configs" do
      Enum.each(1..10, fn _ ->
        config = :crypto.strong_rand_bytes(10) |> Base.encode64()
        pressure_test_and_compare(:get_config, [config])
      end)
    end
  end
end
