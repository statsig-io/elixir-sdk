import Config

Config.config(:statsig,
  api_client: Statsig.TestAPIClient,
  env_tier: "test"
)
