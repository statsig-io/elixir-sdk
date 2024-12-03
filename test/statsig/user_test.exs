defmodule Statsig.UserTest do
  use ExUnit.Case

  alias Statsig.User

  describe "new/2" do
    test "accepts string user_id as first argument" do
      user = User.new("123")
      assert user.user_id == "123"
    end

    test "accepts string user_id with additional params" do
      user = User.new("123", email: "test@example.com")
      assert user.user_id == "123"
      assert user.email == "test@example.com"
    end

    test "accepts custom_ids list as first argument" do
      user = User.new([employee_id: "456"])
      assert user.custom_ids == [employee_id: "456"]
    end

    test "accepts custom_ids with additional params" do
      user = User.new([employee_id: "456"], email: "test@example.com")
      assert user.custom_ids == [employee_id: "456"]
      assert user.email == "test@example.com"
    end

    test "raises when neither user_id nor custom_ids is provided" do
      assert_raise RuntimeError, "You must provide a user id or custom ids", fn ->
        User.new(%{})
      end
    end
  end

  describe "JSON serialization" do
    test "excludes private_attributes when encoding to JSON" do
      user = User.new("123", [
        email: "test@example.com",
        private_attributes: %{"secret" => "value"}
      ])

      json = Jason.encode!(user)
      decoded = Jason.decode!(json)

      assert decoded["user_id"] == "123"
      assert decoded["email"] == "test@example.com"
      refute Map.has_key?(decoded, "private_attributes")
    end

    test "includes all other fields when encoding to JSON" do
      user = User.new("123", [
        email: "test@example.com",
        custom: %{"is_employee" => true},
        custom_ids: [employee_id: "456"],
        ip: "1.2.3.4",
        user_agent: "Mozilla",
        country: "US",
        locale: "en-US",
        app_version: "1.0.0"
      ])

      json = Jason.encode!(user)
      decoded = Jason.decode!(json)

      assert decoded["user_id"] == "123"
      assert decoded["email"] == "test@example.com"
      assert decoded["custom"] == %{"is_employee" => true}
      assert decoded["custom_ids"] == %{"employee_id" => "456"}
      assert decoded["ip"] == "1.2.3.4"
      assert decoded["user_agent"] == "Mozilla"
      assert decoded["country"] == "US"
      assert decoded["locale"] == "en-US"
      assert decoded["app_version"] == "1.0.0"
    end
  end
end
