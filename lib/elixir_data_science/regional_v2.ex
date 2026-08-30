defmodule ElixirDataScience.RegionalV2 do
  @moduledoc """
  Typed, fail-closed boundaries for the publisher-backed regional ensemble v2.

  Version 1 remains immutable. This module owns only v2 contracts, indexed
  artifact receipts, admission profiles, and point-in-time eligibility rules.
  """

  @contract_path Path.expand("../../contracts/regional-expert-ensemble.v2.json", __DIR__)

  defmodule ArtifactReceipt do
    @moduledoc "Integrity metadata for one declared normalized artifact."
    @enforce_keys [:path, :sha256, :byte_count, :row_count]
    defstruct [:path, :sha256, :byte_count, :row_count]

    @type t :: %__MODULE__{
            path: String.t(),
            sha256: String.t(),
            byte_count: non_neg_integer(),
            row_count: non_neg_integer()
          }
  end

  defmodule SourceReceipt do
    @moduledoc "Publisher and custody metadata for one source object."
    @enforce_keys [
      :source_id,
      :publisher_url,
      :release_date,
      :retrieved_at,
      :media_type,
      :sha256,
      :byte_count,
      :terms_url,
      :vintage_status
    ]
    defstruct [
      :source_id,
      :publisher_url,
      :release_date,
      :retrieved_at,
      :media_type,
      :sha256,
      :byte_count,
      :terms_url,
      :vintage_status,
      extraction_tools: %{},
      manual_checks: []
    ]

    @type t :: %__MODULE__{
            source_id: atom(),
            publisher_url: URI.t(),
            release_date: Date.t(),
            retrieved_at: DateTime.t(),
            media_type: String.t(),
            sha256: String.t(),
            byte_count: non_neg_integer(),
            terms_url: URI.t(),
            vintage_status: atom(),
            extraction_tools: %{optional(String.t()) => String.t()},
            manual_checks: [String.t()]
          }
  end

  defmodule PublishedObservation do
    @moduledoc "A normalized source observation with an explicit public release date."
    @enforce_keys [
      :source_id,
      :state_fips,
      :observation_period,
      :release_date,
      :vintage,
      :values
    ]
    defstruct [:source_id, :state_fips, :observation_period, :release_date, :vintage, :values]

    @type t :: %__MODULE__{
            source_id: atom(),
            state_fips: String.t(),
            observation_period: String.t(),
            release_date: Date.t(),
            vintage: String.t(),
            values: %{required(atom()) => float()}
          }
  end

  defmodule Profile do
    @moduledoc "An admitted set of experts and gate-only context sources."
    @enforce_keys [:id, :active?, :experts, :gate_context]
    defstruct [:id, :active?, :experts, :gate_context]

    @type t :: %__MODULE__{
            id: String.t(),
            active?: boolean(),
            experts: [atom()],
            gate_context: [atom()]
          }
  end

  defmodule PanelRow do
    @moduledoc "A typed in-memory v2 panel row before canonical CSV serialization."
    @enforce_keys [
      :forecast_origin,
      :state_fips,
      :target_quarter,
      :target_quarter_number,
      :census_division,
      :evaluation_origin,
      :features,
      :source_release_dates,
      :target,
      :outcome_available_date,
      :target_vintage
    ]
    defstruct [
      :forecast_origin,
      :state_fips,
      :target_quarter,
      :target_quarter_number,
      :census_division,
      :evaluation_origin,
      :features,
      :source_release_dates,
      :target,
      :outcome_available_date,
      :target_vintage
    ]

    @type t :: %__MODULE__{
            forecast_origin: String.t(),
            state_fips: String.t(),
            target_quarter: String.t(),
            target_quarter_number: 1..4,
            census_division: String.t(),
            evaluation_origin: boolean(),
            features: %{optional(atom()) => float()},
            source_release_dates: %{optional(atom()) => Date.t()},
            target: float(),
            outcome_available_date: Date.t(),
            target_vintage: String.t()
          }
  end

  defmodule Prediction do
    @moduledoc "A typed model prediction and interval for one state and origin."
    @enforce_keys [
      :forecast_origin,
      :state_fips,
      :model_id,
      :prediction,
      :final_outcome,
      :error,
      :interval_lower_80,
      :interval_upper_80
    ]
    defstruct [
      :forecast_origin,
      :state_fips,
      :model_id,
      :prediction,
      :final_outcome,
      :error,
      :interval_lower_80,
      :interval_upper_80,
      weights: %{}
    ]

    @type t :: %__MODULE__{
            forecast_origin: String.t(),
            state_fips: String.t(),
            model_id: atom(),
            prediction: float(),
            final_outcome: float(),
            error: float(),
            interval_lower_80: float(),
            interval_upper_80: float(),
            weights: %{optional(atom()) => float()}
          }
  end

  defmodule ModelResult do
    @moduledoc "A typed result for one trained expert or combiner."
    @enforce_keys [:model_id, :predictions, :settings, :metrics]
    defstruct [:model_id, :predictions, :settings, :metrics]

    @type t :: %__MODULE__{
            model_id: atom(),
            predictions: [Prediction.t()],
            settings: map(),
            metrics: %{optional(atom()) => float()}
          }
  end

  defmodule StackResult do
    @moduledoc "Selected experts and exact full-width convex weights."
    @enforce_keys [:selected_experts, :weights, :mse]
    defstruct [:selected_experts, :weights, :mse]

    @type t :: %__MODULE__{
            selected_experts: [atom()],
            weights: %{required(atom()) => float()},
            mse: float()
          }
  end

  @spec load_contract() :: {:ok, map()} | {:error, term()}
  def load_contract do
    with {:ok, bytes} <- File.read(@contract_path),
         {:ok, %{"schema_version" => "regional-expert-ensemble.v2"} = contract} <-
           Jason.decode(bytes) do
      {:ok, contract}
    else
      {:ok, _other} -> {:error, :invalid_v2_contract}
      error -> error
    end
  end

  @spec contract_sha256() :: String.t()
  def contract_sha256 do
    @contract_path
    |> File.read!()
    |> sha256()
  end

  @spec profile(String.t()) :: {:ok, Profile.t()} | {:error, term()}
  def profile(profile_id) when is_binary(profile_id) do
    with {:ok, contract} <- load_contract(),
         %{} = value <- get_in(contract, ["profiles", profile_id]) do
      profile = %Profile{
        id: profile_id,
        active?: Map.get(value, "active", true),
        experts: Enum.map(value["experts"], &known_id!/1),
        gate_context: Enum.map(Map.get(value, "gate_context", []), &known_id!/1)
      }

      if profile.active?, do: {:ok, profile}, else: {:error, {:inactive_profile, profile_id}}
    else
      nil -> {:error, {:unknown_profile, profile_id}}
      error -> error
    end
  end

  @spec artifact_receipt!(Path.t(), String.t(), non_neg_integer()) :: ArtifactReceipt.t()
  def artifact_receipt!(root, relative_path, row_count) do
    bytes = File.read!(Path.join(root, relative_path))

    %ArtifactReceipt{
      path: relative_path,
      sha256: sha256(bytes),
      byte_count: byte_size(bytes),
      row_count: row_count
    }
  end

  @spec validate_artifact(Path.t(), ArtifactReceipt.t()) :: :ok | {:error, term()}
  def validate_artifact(root, %ArtifactReceipt{} = receipt) do
    with :ok <- validate_relative_path(receipt.path),
         :ok <- reject_symlink_components(root, receipt.path),
         path <- Path.join(root, receipt.path),
         {:ok, stat} <- File.lstat(path),
         :ok <- reject_symlink(stat, receipt.path),
         true <- stat.type == :regular,
         {:ok, bytes} <- File.read(path),
         true <- byte_size(bytes) == receipt.byte_count,
         true <- sha256(bytes) == receipt.sha256 do
      :ok
    else
      {:error, _reason} = error -> error
      false -> {:error, {:artifact_receipt_mismatch, receipt.path}}
      _other -> {:error, {:invalid_artifact, receipt.path}}
    end
  end

  @spec first_complete_quarter_origin(
          [PublishedObservation.t()],
          [String.t()],
          String.t(),
          String.t(),
          [non_neg_integer()]
        ) :: {:ok, String.t()} | {:error, :no_complete_origin}
  def first_complete_quarter_origin(observations, states, first, last, lags) do
    first
    |> quarter_stream(last)
    |> Enum.find_value(fn origin ->
      case require_complete_quarter_origin(observations, states, origin, lags) do
        :ok -> {:ok, origin}
        {:error, _reason} -> nil
      end
    end)
    |> case do
      nil -> {:error, :no_complete_origin}
      result -> result
    end
  end

  @spec require_complete_quarter_origin(
          [PublishedObservation.t()],
          [String.t()],
          String.t(),
          [non_neg_integer()]
        ) :: :ok | {:error, {:incomplete_origin, String.t()}}
  def require_complete_quarter_origin(observations, states, origin, lags) do
    origin_end = quarter_end(origin)

    complete? =
      Enum.all?(states, fn state ->
        snapshot =
          observations
          |> Enum.filter(
            &(&1.state_fips == state and Date.compare(&1.release_date, origin_end) != :gt)
          )
          |> Enum.reduce(%{}, fn row, selected ->
            Map.update(selected, row.observation_period, row, fn prior ->
              if Date.compare(prior.release_date, row.release_date) == :lt, do: row, else: prior
            end)
          end)

        case snapshot |> Map.keys() |> Enum.filter(&(&1 <= origin)) |> Enum.max(fn -> nil end) do
          nil -> false
          latest -> Enum.all?(lags, &Map.has_key?(snapshot, quarter_add(latest, -&1)))
        end
      end)

    if complete?, do: :ok, else: {:error, {:incomplete_origin, origin}}
  end

  @spec first_eligible_outer_origin([PanelRow.t()], pos_integer()) ::
          {:ok, String.t()} | {:error, :no_eligible_outer_origin}
  def first_eligible_outer_origin(rows, minimum_quarters) do
    rows
    |> Enum.filter(& &1.evaluation_origin)
    |> Enum.map(& &1.forecast_origin)
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.find_value(fn outer_origin ->
      outer_end = quarter_end(outer_origin)

      eligible_count =
        rows
        |> Enum.filter(fn row ->
          row.forecast_origin < outer_origin and
            Date.compare(row.outcome_available_date, outer_end) != :gt
        end)
        |> Enum.map(& &1.forecast_origin)
        |> Enum.uniq()
        |> length()

      if eligible_count >= minimum_quarters, do: {:ok, outer_origin}
    end)
    |> case do
      nil -> {:error, :no_eligible_outer_origin}
      result -> result
    end
  end

  @spec screened_convex_stack(
          [atom()],
          %{required(atom()) => float()},
          [[float()]],
          [float()]
        ) :: {:ok, StackResult.t()} | {:error, term()}
  def screened_convex_stack(experts, trailing_mae, predictions, outcomes)
      when is_list(experts) and is_map(trailing_mae) and is_list(predictions) and
             is_list(outcomes) do
    with :ok <- validate_stack_inputs(experts, trailing_mae, predictions, outcomes) do
      contract_order = expert_order()

      selected =
        experts
        |> Enum.sort_by(fn expert ->
          {Map.fetch!(trailing_mae, expert), order_index(contract_order, expert)}
        end)
        |> Enum.take(4)

      indices = Enum.map(selected, &Enum.find_index(experts, fn expert -> expert == &1 end))

      selected_predictions =
        Enum.map(predictions, fn row -> Enum.map(indices, &Enum.at(row, &1)) end)

      {selected_weights, mse} = search_simplex(selected_predictions, outcomes)

      weights =
        Map.new(experts, fn expert ->
          case Enum.find_index(selected, fn selected_expert -> selected_expert == expert end) do
            nil -> {expert, 0.0}
            index -> {expert, Enum.at(selected_weights, index)}
          end
        end)

      {:ok, %StackResult{selected_experts: selected, weights: weights, mse: mse}}
    end
  end

  @spec neural_gate_model(pos_integer(), pos_integer()) :: Axon.t()
  def neural_gate_model(input_width, expert_count)
      when is_integer(input_width) and input_width > 0 and is_integer(expert_count) and
             expert_count > 0 do
    "gate_input"
    |> Axon.input(shape: {nil, input_width})
    |> Axon.dense(16, activation: :tanh, name: "gate_hidden")
    |> Axon.dense(expert_count, activation: :softmax, name: "expert_weights")
  end

  @spec quarter_add(String.t(), integer()) :: String.t()
  def quarter_add(quarter, offset),
    do: ElixirDataScience.RegionalExpertEnsemble.quarter_add(quarter, offset)

  @spec quarter_end(String.t()) :: Date.t()
  def quarter_end(quarter), do: ElixirDataScience.RegionalExpertEnsemble.quarter_end(quarter)

  defp quarter_stream(first, last),
    do: Stream.iterate(first, &quarter_add(&1, 1)) |> Enum.take_while(&(&1 <= last))

  defp validate_relative_path(path) do
    expanded = Path.expand(path, "/")

    if Path.type(path) == :relative and expanded == Path.join("/", path) and
         not Enum.member?(Path.split(path), "..") do
      :ok
    else
      {:error, {:unsafe_relative_path, path}}
    end
  end

  defp reject_symlink(%File.Stat{type: :symlink}, path), do: {:error, {:symlink_artifact, path}}
  defp reject_symlink(_stat, _path), do: :ok

  defp reject_symlink_components(root, relative_path) do
    relative_path
    |> Path.split()
    |> Enum.reduce_while(root, fn component, parent ->
      current = Path.join(parent, component)

      case File.lstat(current) do
        {:ok, %File.Stat{type: :symlink}} ->
          {:halt, {:error, {:symlink_artifact, relative_path}}}

        {:ok, _stat} ->
          {:cont, current}

        {:error, reason} ->
          {:halt, {:error, {:artifact_path_error, relative_path, reason}}}
      end
    end)
    |> case do
      {:error, _reason} = error -> error
      _resolved_path -> :ok
    end
  end

  defp known_id!("labor"), do: :labor
  defp known_id!("qcew_business"), do: :qcew_business
  defp known_id!("industry"), do: :industry
  defp known_id!("formation"), do: :formation
  defp known_id!("construction"), do: :construction
  defp known_id!("growth"), do: :growth
  defp known_id!("housing"), do: :housing
  defp known_id!("energy"), do: :energy
  defp known_id!("labor_flows"), do: :labor_flows
  defp known_id!("credit"), do: :credit
  defp known_id!("treasury"), do: :treasury
  defp known_id!(id), do: raise(ArgumentError, "unknown contract identifier: #{id}")

  defp expert_order do
    {:ok, contract} = load_contract()
    Enum.map(contract["expert_order"], &known_id!/1)
  end

  defp order_index(order, expert),
    do: Enum.find_index(order, fn ordered -> ordered == expert end) || length(order)

  defp validate_stack_inputs(experts, trailing_mae, predictions, outcomes) do
    width = length(experts)

    valid? =
      width > 0 and length(predictions) == length(outcomes) and outcomes != [] and
        Enum.uniq(experts) == experts and Enum.all?(experts, &Map.has_key?(trailing_mae, &1)) and
        Enum.all?(predictions, fn row ->
          length(row) == width and Enum.all?(row, &finite_number?/1)
        end) and Enum.all?(outcomes, &finite_number?/1) and
        Enum.all?(Map.take(trailing_mae, experts), fn {_expert, value} ->
          finite_number?(value) and value >= 0
        end)

    if valid?, do: :ok, else: {:error, :invalid_screened_stack_inputs}
  end

  defp search_simplex(predictions, outcomes) do
    width = predictions |> hd() |> length()

    integer_compositions(20, width)
    |> Enum.reduce(nil, fn integers, best ->
      weights = Enum.map(integers, &(&1 / 20.0))

      mse =
        predictions
        |> Enum.zip(outcomes)
        |> Enum.map(fn {row, outcome} ->
          error = Enum.zip_with(row, weights, &*/2) |> Enum.sum() |> Kernel.-(outcome)
          error * error
        end)
        |> then(&(Enum.sum(&1) / length(&1)))

      case best do
        nil -> {weights, mse}
        {_best_weights, best_mse} when mse < best_mse - 1.0e-15 -> {weights, mse}
        current -> current
      end
    end)
  end

  defp integer_compositions(total, 1), do: [[total]]

  defp integer_compositions(total, width) do
    for first <- 0..total,
        rest <- integer_compositions(total - first, width - 1) do
      [first | rest]
    end
  end

  defp finite_number?(value) when is_integer(value), do: true

  defp finite_number?(value) when is_float(value),
    do: value == value and value not in [:infinity, :neg_infinity]

  defp finite_number?(_value), do: false

  defp sha256(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
end
