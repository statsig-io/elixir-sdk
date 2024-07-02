defmodule TestAPIClient do
  def download_config_specs(_key, 0) do
    # "test/data/simple_config.json"
    "test/data/rulesets_e2e_config.json"
    |> Path.expand()
    |> File.read!()
    |> Jason.decode()
  end

  # refreshes should no-op for now
  def download_config_specs(_key, _since) do
    {:ok, %{"has_updates" => false}}
  end

  def push_logs(_key, _logs) do
    {:ok, []}
  end
end
