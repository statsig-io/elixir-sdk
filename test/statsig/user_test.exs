defmodule Statsig.UserTest do
  use ExUnit.Case

  alias Statsig.User

  describe "new/1" do
    test "accepts userID as string key" do
      user = User.new(%{"userID" => "123"})
      assert user.userID == "123"
    end

    test "accepts userID as atom key" do
      user = User.new(%{userID: "123"})
      assert user.userID == "123"
    end

    test "accepts customIDs as string key" do
      user = User.new(%{"customIDs" => %{"employee_id" => "456"}})
      assert user.customIDs == %{"employee_id" => "456"}
    end

    test "accepts customIDs as atom key" do
      user = User.new(%{customIDs: %{"employee_id" => "456"}})
      assert user.customIDs == %{"employee_id" => "456"}
    end

    test "raises when neither userID nor customIDs is provided" do
      assert_raise ArgumentError, "Either userID or customIDs must be provided", fn ->
        User.new(%{email: "test@example.com"})
      end
    end
  end

  describe "JSON serialization" do
    test "excludes privateAttributes when encoding to JSON" do
      user = User.new(%{
        "userID" => "123",
        "email" => "test@example.com",
        "privateAttributes" => %{"secret" => "value"}
      })

      json = Jason.encode!(user)
      decoded = Jason.decode!(json)

      assert decoded["userID"] == "123"
      assert decoded["email"] == "test@example.com"
      refute Map.has_key?(decoded, "privateAttributes")
    end

    test "includes all other fields when encoding to JSON" do
      user = User.new(%{
        "userID" => "123",
        "email" => "test@example.com",
        "custom" => %{"is_employee" => true},
        "customIDs" => %{"employee_id" => "456"},
        "ip" => "1.2.3.4",
        "userAgent" => "Mozilla",
        "country" => "US",
        "locale" => "en-US",
        "appVersion" => "1.0.0"
      })

      json = Jason.encode!(user)
      decoded = Jason.decode!(json)

      assert decoded["userID"] == "123"
      assert decoded["email"] == "test@example.com"
      assert decoded["custom"] == %{"is_employee" => true}
      assert decoded["customIDs"] == %{"employee_id" => "456"}
      assert decoded["ip"] == "1.2.3.4"
      assert decoded["userAgent"] == "Mozilla"
      assert decoded["country"] == "US"
      assert decoded["locale"] == "en-US"
      assert decoded["appVersion"] == "1.0.0"
    end
  end
end
