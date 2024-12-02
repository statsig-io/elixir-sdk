defmodule Statsig.User do
  @derive {Jason.Encoder, only: [
    :user_id,
    :custom_ids,
    :email,
    :ip,
    :user_agent,
    :country,
    :locale,
    :app_version,
    :custom,
    :statsig_environment
  ]}

  @type custom_value :: String.t() | number() | boolean() | nil
  @type custom_attributes :: %{optional(String.t()) => custom_value()}

  @type t :: %__MODULE__{
    user_id: String.t() | nil,
    custom_ids: %{optional(String.t()) => String.t()} | nil,
    email: String.t() | nil,
    ip: String.t() | nil,
    user_agent: String.t() | nil,
    country: String.t() | nil,
    locale: String.t() | nil,
    app_version: String.t() | nil,
    custom: custom_attributes() | nil,
    private_attributes: custom_attributes() | nil,
    statsig_environment: map() | nil
  }

  defstruct [
    :user_id,
    :custom_ids,
    :email,
    :ip,
    :user_agent,
    :country,
    :locale,
    :app_version,
    :custom,
    :private_attributes,
    :statsig_environment
  ]

  def new(user_id_or_custom_ids, params \\ [])

  def new(custom_ids = [_ | _], params) do
    struct(__MODULE__, Keyword.merge(params, custom_ids: custom_ids))
  end

  def new(user_id, params) when is_binary(user_id) do
    struct(__MODULE__, Keyword.merge(params, user_id: user_id))
  end

  def new(_, _), do: raise("You must provide a user id or custom ids")

  defp new_from_params(params) do
    params =
      Keyword.new(params, fn
        {key, _v} = key_and_value when is_atom(key) -> key_and_value
        {key, value} when is_binary(key) -> {String.to_existing_atom(key), value}
      end)
    struct(__MODULE__, params)
  end

  def encode_as(key) when is_atom(key) do
    case key do
      :user_id -> "userID"
      :custom_ids -> "customIDs"
      :user_agent -> "userAgent"
      :app_version -> "appVersion"
      :statsig_environment -> "statsigEnvironment"
      _ -> key |> Atom.to_string()
    end
  end
end
