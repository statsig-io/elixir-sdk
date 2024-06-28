use Mix.Config

config :statsig_ex, api_client: TestAPIClient

# this is for configuring the statsig_erl lib
config :statsig,
  network: :test_network,
  statsig_api_key: "123"
