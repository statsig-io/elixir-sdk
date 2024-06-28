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

  describe "dynamic configs" do
    test "basic props pass" do
      assert %{"hello" => "world"} == StatsigEx.get_config(%{"userID" => "pass"}, "basic-props")
    end

    test "basic props fail" do
      assert %{"hello" => "nobody"} == StatsigEx.get_config(%{}, "basic-props")
    end
  end

  describe "experiments" do
    test "basic 50/50 test returns expected value" do
      assert %{"test" => "test"} == StatsigEx.get_experiment(%{}, "basic-a-b")
      # just so happens that this particular userID hashes to a value that is in the control
      assert %{"test" => "control"} == StatsigEx.get_config(%{"userID" => "control"}, "basic-a-b")
    end

    @tag :flakey
    test "segmentation for basic 50/50 test is in expected tolerances" do
      {test, control} =
        Enum.reduce(1..10_000, {0, 0}, fn _, {t, c} ->
          id = :crypto.strong_rand_bytes(10) |> Base.encode64()

          case StatsigEx.get_experiment(%{"userID" => id}, "basic-a-b") do
            %{"test" => "control"} -> {t, c + 1}
            _ -> {t + 1, c}
          end
        end)

      assert test / control > 0.95 && test / control < 1.05
    end
  end
end
