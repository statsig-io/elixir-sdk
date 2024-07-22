use Mix.Config

config :statsig_ex,
  api_client: StatsigEx.TestAPIClient,
  env_tier: "test"

# this is for configuring the statsig_erl lib
config :statsig,
  network: :test_network,
  statsig_api_key: "123",
  statsig_environment_tier: "test"
