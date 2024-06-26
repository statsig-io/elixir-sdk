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
end
