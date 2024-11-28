defmodule Statsig.EvaluationResult do
  defstruct exposures: [],
            secondary_exposures: [],
            raw_result: false,
            result: false,
            reason: nil,
            rule: %{},
            value: nil
end
