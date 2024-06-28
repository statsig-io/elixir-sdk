defmodule StatsigExTest do
  use ExUnit.Case
  doctest StatsigEx

  test "non-existent flag returns false" do
    refute StatsigEx.check_flag(%{"userID" => "whatever"}, "doesnt-exist-anywhere")
  end

  test "disabled flag returns false" do
    refute StatsigEx.check_flag(%{"userID" => "anyone"}, "disabled")
  end

  describe "flag with 'Everyone' condition, 100% pass" do
    test "matches all" do
      assert StatsigEx.check_flag(%{"userID" => "phil"}, "public")
      assert StatsigEx.check_flag(%{"userID" => "other"}, "public")
    end
  end

  test "flag with 'Everyone' condition, 0% pass fails all" do
    refute StatsigEx.check_flag(%{"userID" => "phil"}, "public-0-perc")
    refute StatsigEx.check_flag(%{"userID" => "other"}, "public-0-perc")
  end

  test "flag with 'Everyone' condition, 99% pass passes" do
    assert StatsigEx.check_flag(%{"userID" => "phil"}, "public-99-perc")
  end

  test "flag with 'Everyone' condition, 1% pass fails" do
    refute StatsigEx.check_flag(%{"userID" => "phil"}, "public-1-perc")
  end

  describe "pass_gate flag" do
    test "that is 100% and proxied to gate that is 100% pass for everyone should pass" do
      assert StatsigEx.check_flag(%{"userID" => "phil"}, "pass-gate")
    end

    test "that is 0% pass and proxied to a gete that is 100% pass for everyone should fail" do
      refute StatsigEx.check_flag(%{"userID" => "phil"}, "pass-gate-0-perc")
    end
  end

  describe "fail_gate flag" do
    test "that is 100% and proxied to gate that is 0% pass for everyone should pass" do
      assert StatsigEx.check_flag(%{"userID" => "phil"}, "fail-gate-open")
    end

    test "that is 100% and proxied to gate that is 100% pass for everyone should fail" do
      refute StatsigEx.check_flag(%{"userID" => "phil"}, "fail-gate-closed")
    end
  end

  describe "user_field gate" do
    test "user ID is in list" do
      assert StatsigEx.check_flag(%{"userID" => "phil"}, "user-field-userid-is-in")
    end

    test "user ID is NOT in the list" do
      refute StatsigEx.check_flag(%{"userID" => "nope"}, "user-field-userid-is-in")
    end
  end

  describe "environment_field gate" do
    test "environment value is in list" do
      assert StatsigEx.check_flag(
               %{"userID" => "test", "statsigEnvironment" => %{"tier" => "production"}},
               "env-field-production-tier-is-in"
             )
    end
  end

  describe "current_time gate" do
    test "time is after 6/1/24" do
      assert StatsigEx.check_flag(%{}, "time-after-x")
    end
  end

  describe "segments" do
    test "simple conditional segment" do
      assert StatsigEx.check_flag(%{"userID" => "phil"}, "simple-segment")
    end
  end

  describe "customer ID gate" do
    test "is in list" do
      assert StatsigEx.check_flag(
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
      assert StatsigEx.check_flag(%{"appVersion" => "1.1.1"}, "version-greater-than")
      refute StatsigEx.check_flag(%{"appVersion" => "0.9.0"}, "version-greater-than")
    end

    test "less than version works as expected" do
      refute StatsigEx.check_flag(%{"appVersion" => "1.8.2"}, "version-less-than")
      assert StatsigEx.check_flag(%{"appVersion" => "0.7.0-alpha"}, "version-less-than")
      assert StatsigEx.check_flag(%{"appVersion" => "0.6.9"}, "version-less-than")
    end
  end

  describe "vs. the erlang client" do
    test "non-existent gate" do
      {user, gate} = {%{"userID" => "whatever"}, "doesnt-exist-anywhere"}
      assert StatsigEx.check_flag(user, gate) == :statsig.check_gate(user, gate)
    end

    test "disabled flag" do
      {user, gate} = {%{"userID" => "anyone"}, "disabled"}
      assert StatsigEx.check_flag(user, gate) == :statsig.check_gate(user, gate)
    end

    test "segmentation of experiment is exactly the same" do
      gate = "basic-a-b"

      pressure_test_and_compare(:get_experiment, [gate])
    end
  end

  describe "dynamic configs" do
    # probaly just need to iterate over a bunch of different variations of user on all these things
    test "basic props pass" do
      assert StatsigEx.get_config(%{"userID" => "pass"}, "basic-props") ==
               :statsig.get_config(%{"userID" => "pass"}, "basic-props")
    end

    test "basic props that fail fallback properly" do
      pressure_test_and_compare(:get_config, ["basic-props"])
    end
  end

  defp pressure_test_and_compare(func, args, iterations \\ 10_000) do
    {misses, results} =
      Enum.reduce(1..iterations, {0, []}, fn _, {m, r} ->
        id = :crypto.strong_rand_bytes(10) |> Base.encode64()
        # we should put a bunch more data in here to be sure
        user = %{"userID" => id}
        # function name & arity must be the same in both (this is a good restriction)
        ex_result = apply(StatsigEx, func, [user | args])
        erl_result = apply(:statsig, func, [user | args])

        case {ex_result, erl_result} do
          {a, b} when a == b -> {m, r}
          {a, b} -> {m + 1, [{a, b} | r]}
        end
      end)

    assert misses == 0, "expected 0 misses, but got #{misses} : #{inspect(List.first(results))}"
  end
end
