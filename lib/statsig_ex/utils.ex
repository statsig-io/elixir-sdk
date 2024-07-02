defmodule StatsigEx.Utils do
  def get_user_with_env(%{"statsigEnvironment" => env} = user) when not is_nil(env), do: user
  def get_user_with_env(%{} = user), do: put_env(user)

  defp put_env(user) do
    case Application.get_env(:statsig_ex, :env_tier) do
      nil -> user
      tier -> Map.put(user, "statsigEnvironment", %{"tier" => tier})
    end
  end
end
