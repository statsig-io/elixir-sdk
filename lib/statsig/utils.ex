defmodule Statsig.Utils do
  alias Statsig.User

  def get_user_with_env(%User{statsigEnvironment: env} = user) when not is_nil(env),
    do: user

  def get_user_with_env(%User{} = user), do: put_env(user)

  def sanitize_user(%User{} = user), do: %User{user | privateAttributes: nil}

  defp put_env(%User{} = user) do
    case Application.get_env(:statsig, :env_tier) do
      nil -> user
      tier -> %User{user | statsigEnvironment: %{"tier" => tier}}
    end
  end
end
