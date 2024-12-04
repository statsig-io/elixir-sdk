defmodule Statsig.DynamicConfig do
  @type secondary_exposure :: %{
    gate: String.t(),
    gateValue: String.t(),
    ruleID: String.t()
  }

  @type t :: %__MODULE__{
    name: String.t(),
    value: map(),
    rule_id: String.t(),
    group_name: String.t() | nil,
    id_type: String.t() | nil,
    secondary_exposures: [secondary_exposure()]
  }

  defstruct [
    :name,
    :value,
    :rule_id,
    :group_name,
    :id_type,
    secondary_exposures: []
  ]

  @spec new(
    String.t(),
    map(),
    String.t() | nil,
    String.t() | nil,
    String.t() | nil,
    [secondary_exposure()] | nil
  ) :: t()
  def new(
    config_name,
    value,
    rule_id,
    group_name,
    id_type,
    secondary_exposures
  ) do
    %__MODULE__{
      name: config_name || "",
      value: value || %{},
      rule_id: rule_id,
      group_name: group_name,
      id_type: id_type,
      secondary_exposures: secondary_exposures || []
    }
  end
end
