defmodule Statsig.Utils do
  alias Statsig.User

  def get_user_with_env(%User{statsig_environment: env} = user) when not is_nil(env),
    do: user

  def get_user_with_env(%User{} = user), do: put_statsig_env(user)

  def sanitize_user(%User{} = user), do: %User{user | private_attributes: nil}

  defp put_statsig_env(%User{} = user) do
    case Application.get_env(:statsig, :env_tier) do
      nil -> user
      tier -> %User{user | statsig_environment: %{"tier" => tier}}
    end
  end
end
