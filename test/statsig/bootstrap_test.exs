defmodule Statsig.BootstrapTest do
  use ExUnit.Case

  @moduletag :capture_log

  setup do
    # Stop the application if it's running
    Application.stop(:statsig)

    # Read and set bootstrap data
    bootstrap_data =
      "test/data/rulesets_e2e_config.json"
      |> File.read!()
      |> Jason.decode!()

    Application.put_env(:statsig, :bootstrap_config_specs, bootstrap_data)

    # Now start the application with bootstrap data in place
    start_supervised!(%{
      id: Statsig.Application,
      start: {Statsig.Application, :start, [:normal, []]}
    })

    on_exit(fn ->
      Application.delete_env(:statsig, :bootstrap_config_specs)
    end)

    :ok
  end

  test "uses bootstrapped gate values" do
    {:ok, result} = Statsig.check_gate(%Statsig.User{user_id: "12345"}, "test_numeric_user_id")
    assert result == true
  end

  test "uses bootstrapped config values" do
    {:ok, result} = Statsig.get_config(%Statsig.User{user_id: "123", email: "jkw@statsig.com"}, "test_email_config")

    assert %Statsig.DynamicConfig{
      value: %{
        "header_text" => "jkw only"
      }
    } = result
  end

end
