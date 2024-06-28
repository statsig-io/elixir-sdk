defmodule StatsigEx.PressureTest do
  import ExUnit.Assertions

  def pressure_test_and_compare(func, args, iterations \\ 10_000) do
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
