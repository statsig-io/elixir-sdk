defmodule Statsig.Utils do
  def get_user_with_env(user, tier \\ nil)

  def get_user_with_env(%{"statsigEnvironment" => env} = user, _tier) when not is_nil(env),
    do: user

  def get_user_with_env(%{} = user, tier), do: put_env(user, tier)

  def sanitize_user(user), do: Map.delete(user, "privateAttributes")

  defp put_env(user, nil) do
    case Application.get_env(:statsig, :env_tier) do
      nil -> user
      tier -> Map.put(user, "statsigEnvironment", %{"tier" => tier})
    end
  end

  defp put_env(user, tier),
    do: Map.put(user, "statsigEnvironment", %{"tier" => tier})
end
