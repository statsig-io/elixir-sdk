defmodule Statsig.User do
  @derive {Jason.Encoder, only: [
    :userID,
    :customIDs,
    :email,
    :ip,
    :userAgent,
    :country,
    :locale,
    :appVersion,
    :custom,
    :statsigEnvironment
  ]}

  @type custom_value :: String.t() | number() | boolean() | nil
  @type custom_attributes :: %{optional(String.t()) => custom_value()}

  @type t :: %__MODULE__{
    userID: String.t() | nil,
    customIDs: %{optional(String.t()) => String.t()} | nil,
    email: String.t() | nil,
    ip: String.t() | nil,
    userAgent: String.t() | nil,
    country: String.t() | nil,
    locale: String.t() | nil,
    appVersion: String.t() | nil,
    custom: custom_attributes() | nil,
    privateAttributes: custom_attributes() | nil,
    statsigEnvironment: map() | nil
  }

  defstruct userID: nil,
            customIDs: nil,
            email: nil,
            ip: nil,
            userAgent: nil,
            country: nil,
            locale: nil,
            appVersion: nil,
            custom: nil,
            privateAttributes: nil,
            statsigEnvironment: nil

  def new(params \\ %{}) do
    unless Map.get(params, "userID") || Map.get(params, :userID) ||
           Map.get(params, "customIDs") || Map.get(params, :customIDs) do
      raise ArgumentError, "Either userID or customIDs must be provided"
    end

    converted_params = for {key, val} <- params, into: %{} do
      cond do
        is_binary(key) -> {String.to_existing_atom(key), val}
        is_atom(key) -> {key, val}
        true -> {key, val}
      end
    end

    struct(__MODULE__, converted_params)
  end
end
