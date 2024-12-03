defmodule Statsig.User do
  @derive {Jason.Encoder, except: [:private_attributes]}
  defstruct [:user_id, :email, :custom, :custom_ids, :private_attributes,
            :ip, :user_agent, :country, :locale, :app_version, :statsig_environment]

  @type custom_value :: String.t() | number() | boolean() | nil
  @type custom_attributes :: %{String.t() => custom_value()}

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

  def new(user_id_or_custom_ids, params \\ [])

  def new(custom_ids = [_ | _], params) do
    struct(__MODULE__, Keyword.merge(params, custom_ids: custom_ids))
  end

  def new(user_id, params) when is_binary(user_id) do
    struct(__MODULE__, Keyword.merge(params, user_id: user_id))
  end

  def new(_, _), do: raise("You must provide a user id or custom ids")

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

  defimpl Jason.Encoder do
    def encode(user, opts) do
      user
      |> Map.from_struct()
      |> Map.delete(:private_attributes)
      |> Map.update!(:custom_ids, fn custom_ids ->
        custom_ids && Map.new(custom_ids)
      end)
      |> Enum.reject(&match?({_, nil},&1))
      |> Map.new(fn {key, value} ->
        {Statsig.User.encode_as(key), value}
        end)
      |> Jason.Encode.map(opts)
    end
  end
end
