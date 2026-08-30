defmodule ElixirDataScience.RegionalModeling do
  @moduledoc "Offline ridge experts, expanding backtest, convex stack, and artifact writer."

  alias ElixirDataScience.RegionalExpertEnsemble, as: Regional
  alias Scholar.Linear.RidgeRegression

  @repository_root Path.expand("../..", __DIR__)

  @experts [
    {"labor", ["qcew_employment_yoy", "qcew_employment_qoq", "qcew_employment_yoy_lag1"]},
    {"business", ["qcew_establishments_yoy", "qcew_total_wages_yoy"]},
    {"growth",
     [
       "bea_real_gdp_yoy",
       "bea_real_gdp_qoq",
       "bea_personal_income_yoy",
       "bea_personal_income_qoq"
     ]},
    {"housing", ["fhfa_hpi_qoq", "fhfa_hpi_yoy"]}
  ]
  @alphas [0.01, 0.1, 1.0, 10.0, 100.0]
  @prediction_columns [
    "forecast_origin",
    "state_fips",
    "target_quarter",
    "census_division",
    "model_id",
    "prediction",
    "final_outcome",
    "error",
    "interval_lower_80",
    "interval_upper_80",
    "weight_labor",
    "weight_business",
    "weight_growth",
    "weight_housing",
    "contribution_labor",
    "contribution_business",
    "contribution_growth",
    "contribution_housing",
    "alpha"
  ]

  @type matrix :: [[float()]]
  @type weight_vector :: [float()]

  @spec run(Path.t(), Path.t()) :: {:ok, Regional.json_object()} | {:error, term()}
  def run(bundle_path, output_dir) do
    Nx.global_default_backend(EXLA.Backend)
    Nx.Defn.global_default_options(compiler: EXLA)

    with {:ok, bytes} <- File.read(bundle_path),
         {:ok, bundle} <- Jason.decode(bytes),
         {:ok, panel} <- Regional.build_panel(bundle) do
      folds = Regional.build_folds(panel)
      predictions = backtest(panel, folds)

      if predictions == [] do
        {:error, :no_eligible_forecasts}
      else
        File.mkdir_p!(output_dir)
        panel_columns = panel |> hd() |> Map.keys() |> panel_column_order()

        fold_columns = [
          "outer_origin",
          "membership",
          "row_origin",
          "state_fips",
          "target_quarter",
          "outcome_available_date"
        ]

        artifacts = %{
          "regional-panel.v1.csv" => Regional.canonical_csv(panel, panel_columns),
          "regional-folds.v1.csv" => Regional.canonical_csv(folds, fold_columns),
          "regional-predictions.v1.csv" =>
            Regional.canonical_csv(predictions, @prediction_columns)
        }

        Enum.each(artifacts, fn {name, artifact_bytes} ->
          File.write!(Path.join(output_dir, name), artifact_bytes)
        end)

        {:ok, contract} = Regional.load_contract()

        row_counts = %{
          "regional-panel.v1.csv" => length(panel),
          "regional-folds.v1.csv" => length(folds),
          "regional-predictions.v1.csv" => length(predictions)
        }

        manifest = %{
          "schema_version" => "regional-run-manifest.v1",
          "contract_sha256" => Regional.contract_sha256(),
          "source_bundle_sha256" => sha256(bytes),
          "artifacts" =>
            Map.new(artifacts, fn {name, artifact_bytes} ->
              {name,
               %{
                 "sha256" => sha256(artifact_bytes),
                 "byte_count" => byte_size(artifact_bytes),
                 "row_count" => row_counts[name]
               }}
            end),
          "environment" => %{
            "implementation" => "elixir",
            "elixir" => System.version(),
            "erlang_otp" => System.otp_release(),
            "platform" => :erlang.system_info(:system_architecture) |> to_string()
          },
          "git" => git_state(),
          "settings" => %{
            "ridge" => contract["ridge"],
            "stack" => contract["stack"],
            "neural_gate" => contract["neural_gate"],
            "intervals" => contract["intervals"]
          },
          "metrics" => metrics(predictions),
          "exclusions" => contract["excluded_v1"],
          "claims" => contract["claims"]
        }

        File.write!(
          Path.join(output_dir, "regional-run-manifest.v1.json"),
          Regional.canonical_json(manifest)
        )

        {:ok, manifest}
      end
    end
  end

  @spec backtest([Regional.row()], [Regional.row()]) :: [Regional.row()]
  def backtest(panel, folds) do
    panel_by_key = Map.new(panel, &{{&1["forecast_origin"], &1["state_fips"]}, &1})
    all_oof = oof_predictions(panel)

    folds
    |> Enum.map(& &1["outer_origin"])
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.flat_map(fn outer_origin ->
      fold = Enum.filter(folds, &(&1["outer_origin"] == outer_origin))

      train =
        fold
        |> Enum.filter(&(&1["membership"] == "train"))
        |> Enum.map(&panel_by_key[{&1["row_origin"], &1["state_fips"]}])

      forecast =
        fold
        |> Enum.filter(&(&1["membership"] == "forecast"))
        |> Enum.map(&panel_by_key[{outer_origin, &1["state_fips"]}])

      expert_results =
        Enum.map(@experts, fn {expert, features} ->
          alpha = select_alpha(train, features)
          {expert, alpha, ridge_predict(train, forecast, features, alpha)}
        end)

      forecast_matrix = transpose(Enum.map(expert_results, &elem(&1, 2)))
      pooled_features = Enum.flat_map(@experts, &elem(&1, 1))
      pooled_alpha = select_alpha(train, pooled_features)
      pooled = ridge_predict(train, forecast, pooled_features, pooled_alpha)

      oof_indexes =
        all_oof.rows
        |> Enum.with_index()
        |> Enum.filter(fn {row, _index} ->
          row["forecast_origin"] < outer_origin and
            Date.compare(
              Date.from_iso8601!(row["outcome_available_date"]),
              Regional.quarter_end(outer_origin)
            ) in [:lt, :eq]
        end)
        |> Enum.map(&elem(&1, 1))

      oof_rows = Enum.map(oof_indexes, &Enum.at(all_oof.rows, &1))
      oof_matrix = Enum.map(oof_indexes, &Enum.at(all_oof.expert_predictions, &1))
      oof_pooled = Enum.map(oof_indexes, &Enum.at(all_oof.pooled_predictions, &1))
      oof_targets = Enum.map(oof_indexes, &Enum.at(all_oof.targets, &1))

      {stack_weights, inverse_weights, radii} =
        if oof_rows == [] do
          weights = [0.25, 0.25, 0.25, 0.25]

          model_ids =
            Enum.map(@experts, &elem(&1, 0)) ++
              [
                "zero",
                "latest_qcew_yoy",
                "pooled_ridge",
                "equal_weight",
                "inverse_mae",
                "convex_stack"
              ]

          {weights, weights, Map.new(model_ids, &{&1, 0.0})}
        else
          stack = Regional.search_convex_stack(oof_matrix, oof_targets)
          maes = column_maes(oof_matrix, oof_targets)
          inverse = normalize(Enum.map(maes, &(1.0 / max(&1, 1.0e-12))))

          expert_radii =
            oof_matrix
            |> transpose()
            |> Enum.zip(Enum.map(@experts, &elem(&1, 0)))
            |> Map.new(fn {values, expert_id} ->
              {expert_id, empirical_radius(values, oof_targets)}
            end)

          other_radii = %{
            "zero" => empirical_radius(List.duplicate(0.0, length(oof_targets)), oof_targets),
            "latest_qcew_yoy" =>
              empirical_radius(
                Enum.map(oof_rows, &(&1["qcew_employment_yoy"] * 1.0)),
                oof_targets
              ),
            "pooled_ridge" => empirical_radius(oof_pooled, oof_targets),
            "equal_weight" => empirical_radius(Enum.map(oof_matrix, &average/1), oof_targets),
            "inverse_mae" =>
              empirical_radius(Enum.map(oof_matrix, &dot(&1, inverse)), oof_targets),
            "convex_stack" => empirical_radius(Enum.map(oof_matrix, &dot(&1, stack)), oof_targets)
          }

          {stack, inverse, Map.merge(expert_radii, other_radii)}
        end

      equal = Enum.map(forecast_matrix, &(Enum.sum(&1) / 4.0))
      inverse = Enum.map(forecast_matrix, &dot(&1, inverse_weights))
      stack = Enum.map(forecast_matrix, &dot(&1, stack_weights))

      expert_models =
        expert_results
        |> Enum.with_index()
        |> Enum.map(fn {{expert_id, alpha, values}, index} ->
          %{
            id: expert_id,
            values: values,
            weights: one_hot(index),
            alpha: alpha,
            radius: radii[expert_id]
          }
        end)

      models =
        expert_models ++
          [
            %{
              id: "zero",
              values: List.duplicate(0.0, length(forecast)),
              weights: nil,
              alpha: "",
              radius: radii["zero"]
            },
            %{
              id: "latest_qcew_yoy",
              values: Enum.map(forecast, &(&1["qcew_employment_yoy"] * 1.0)),
              weights: nil,
              alpha: "",
              radius: radii["latest_qcew_yoy"]
            },
            %{
              id: "pooled_ridge",
              values: pooled,
              weights: nil,
              alpha: pooled_alpha,
              radius: radii["pooled_ridge"]
            },
            %{
              id: "equal_weight",
              values: equal,
              weights: [0.25, 0.25, 0.25, 0.25],
              alpha: "",
              radius: radii["equal_weight"]
            },
            %{
              id: "inverse_mae",
              values: inverse,
              weights: inverse_weights,
              alpha: "",
              radius: radii["inverse_mae"]
            },
            %{
              id: "convex_stack",
              values: stack,
              weights: stack_weights,
              alpha: "",
              radius: radii["convex_stack"]
            }
          ]

      models =
        if oof_rows |> Enum.map(& &1["forecast_origin"]) |> Enum.uniq() |> length() >= 8 do
          {neural_predictions, neural_weights, neural_radius} =
            neural_gate(oof_rows, oof_matrix, oof_targets, forecast, forecast_matrix)

          models ++
            [
              %{
                id: "neural_gate",
                values: neural_predictions,
                weights: neural_weights,
                alpha: "",
                radius: neural_radius
              }
            ]
        else
          models
        end

      Enum.with_index(forecast)
      |> Enum.flat_map(fn {row, index} ->
        outcome = row["target_employment_growth_yoy"] * 1.0

        Enum.map(models, fn model ->
          prediction = Enum.at(model.values, index)
          weights = row_weights(model.weights, index)
          contributions = row_contributions(weights, forecast_matrix, index)

          %{
            "forecast_origin" => outer_origin,
            "state_fips" => row["state_fips"],
            "target_quarter" => row["target_quarter"],
            "census_division" => row["census_division"],
            "model_id" => model.id,
            "prediction" => prediction,
            "final_outcome" => outcome,
            "error" => prediction - outcome,
            "interval_lower_80" => prediction - model.radius,
            "interval_upper_80" => prediction + model.radius,
            "weight_labor" => Enum.at(weights, 0),
            "weight_business" => Enum.at(weights, 1),
            "weight_growth" => Enum.at(weights, 2),
            "weight_housing" => Enum.at(weights, 3),
            "contribution_labor" => Enum.at(contributions, 0),
            "contribution_business" => Enum.at(contributions, 1),
            "contribution_growth" => Enum.at(contributions, 2),
            "contribution_housing" => Enum.at(contributions, 3),
            "alpha" => model.alpha
          }
        end)
      end)
    end)
    |> Enum.sort_by(&{&1["forecast_origin"], &1["state_fips"], &1["model_id"]})
  end

  defp oof_predictions(train) do
    pooled_features = Enum.flat_map(@experts, &elem(&1, 1))

    train
    |> Enum.map(& &1["forecast_origin"])
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.reduce(
      %{rows: [], expert_predictions: [], pooled_predictions: [], targets: []},
      fn origin, acc ->
        prior =
          Enum.filter(
            train,
            &(&1["forecast_origin"] < origin and
                Date.compare(
                  Date.from_iso8601!(&1["outcome_available_date"]),
                  Regional.quarter_end(origin)
                ) in [:lt, :eq])
          )

        if prior |> Enum.map(& &1["forecast_origin"]) |> Enum.uniq() |> length() < 8 do
          acc
        else
          validation = Enum.filter(train, &(&1["forecast_origin"] == origin))

          columns =
            Enum.map(@experts, fn {_expert, features} ->
              ridge_predict(prior, validation, features, select_alpha(prior, features))
            end)

          pooled =
            ridge_predict(
              prior,
              validation,
              pooled_features,
              select_alpha(prior, pooled_features)
            )

          %{
            rows: acc.rows ++ validation,
            expert_predictions: acc.expert_predictions ++ transpose(columns),
            pooled_predictions: acc.pooled_predictions ++ pooled,
            targets:
              acc.targets ++
                Enum.map(validation, &(&1["target_employment_growth_yoy"] * 1.0))
          }
        end
      end
    )
  end

  defp row_weights(nil, _index), do: ["", "", "", ""]

  defp row_weights([first | _rest] = weights, index) when is_list(first),
    do: Enum.at(weights, index)

  defp row_weights(weights, _index), do: weights

  defp row_contributions(["", "", "", ""], _forecast_matrix, _index),
    do: ["", "", "", ""]

  defp row_contributions(weights, forecast_matrix, index) do
    forecast_matrix
    |> Enum.at(index)
    |> Enum.zip(weights)
    |> Enum.map(fn {prediction, weight} -> prediction * weight end)
  end

  defp one_hot(selected),
    do: Enum.map(0..3, &if(&1 == selected, do: 1.0, else: 0.0))

  defp neural_gate(oof_rows, oof_matrix, oof_targets, forecast, forecast_matrix) do
    quarter_ids = Enum.map(oof_rows, & &1["forecast_origin"])
    trailing = trailing_mae_matrix(oof_matrix, oof_targets, quarter_ids)
    oof_features = append_columns(oof_matrix, trailing, context_matrix(oof_rows))
    forecast_mae = List.duplicate(column_maes(oof_matrix, oof_targets), length(forecast_matrix))
    forecast_features = append_columns(forecast_matrix, forecast_mae, context_matrix(forecast))

    validation_quarters =
      oof_rows
      |> Enum.map(& &1["forecast_origin"])
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.take(-4)
      |> MapSet.new()

    {train_indices, validation_indices} =
      oof_rows
      |> Enum.with_index()
      |> Enum.split_with(fn {row, _index} ->
        not MapSet.member?(validation_quarters, row["forecast_origin"])
      end)
      |> then(fn {train, validation} ->
        {Enum.map(train, &elem(&1, 1)), Enum.map(validation, &elem(&1, 1))}
      end)

    {standardized_oof, standardized_forecast} =
      standardize_gate(oof_features, forecast_features, train_indices)

    input_width = standardized_oof |> hd() |> length()
    {prediction_model, weights_model} = gate_models(input_width)
    train_data = gate_data(standardized_oof, oof_matrix, oof_targets, train_indices)
    validation_data = gate_data(standardized_oof, oof_matrix, oof_targets, validation_indices)

    model_state =
      prediction_model
      |> Axon.Loop.trainer(
        :mean_squared_error,
        Polaris.Optimizers.adam(learning_rate: 0.01),
        seed: 42,
        log: 0
      )
      |> Axon.Loop.validate(prediction_model, validation_data)
      |> Axon.Loop.early_stop("validation_loss", patience: 30)
      |> Axon.Loop.run(train_data, Axon.ModelState.empty(), epochs: 500, iterations: 1)

    inputs = %{
      "gate_input" => Nx.tensor(standardized_forecast, type: {:f, 32}),
      "experts" => Nx.tensor(forecast_matrix, type: {:f, 32})
    }

    predictions = prediction_model |> Axon.predict(model_state, inputs) |> Nx.to_flat_list()
    weights = weights_model |> Axon.predict(model_state, inputs) |> Nx.to_list()

    calibration_inputs = %{
      "gate_input" =>
        Nx.tensor(Enum.map(validation_indices, &Enum.at(standardized_oof, &1)), type: {:f, 32}),
      "experts" =>
        Nx.tensor(Enum.map(validation_indices, &Enum.at(oof_matrix, &1)), type: {:f, 32})
    }

    calibration_predictions =
      prediction_model
      |> Axon.predict(model_state, calibration_inputs)
      |> Nx.to_flat_list()

    calibration_targets = Enum.map(validation_indices, &Enum.at(oof_targets, &1))
    {predictions, weights, empirical_radius(calibration_predictions, calibration_targets)}
  end

  defp gate_models(input_width) do
    gate_input = Axon.input("gate_input", shape: {nil, input_width})
    experts = Axon.input("experts", shape: {nil, 4})

    weights =
      gate_input
      |> Axon.dense(16, activation: :tanh, name: "gate_hidden")
      |> Axon.dense(4, activation: :softmax, name: "expert_weights")

    prediction =
      weights
      |> Axon.multiply(experts)
      |> Axon.nx(&Nx.sum(&1, axes: [1]))

    {prediction, weights}
  end

  defp gate_data(features, experts, targets, indices) do
    inputs = %{
      "gate_input" => Nx.tensor(Enum.map(indices, &Enum.at(features, &1)), type: {:f, 32}),
      "experts" => Nx.tensor(Enum.map(indices, &Enum.at(experts, &1)), type: {:f, 32})
    }

    labels = Nx.tensor(Enum.map(indices, &Enum.at(targets, &1)), type: {:f, 32})
    [{inputs, labels}]
  end

  defp standardize_gate(oof, forecast, train_indices) do
    width = oof |> hd() |> length()

    {means, scales} =
      0..(width - 1)
      |> Enum.map(fn column ->
        values = Enum.map(train_indices, &(oof |> Enum.at(&1) |> Enum.at(column)))
        mean = average(values)
        variance = values |> Enum.map(&:math.pow(&1 - mean, 2)) |> average()
        {mean, if(variance == 0.0, do: 1.0, else: :math.sqrt(variance))}
      end)
      |> Enum.unzip()

    standardize = fn rows ->
      Enum.map(rows, fn row ->
        Enum.with_index(row)
        |> Enum.map(fn {value, index} ->
          (value - Enum.at(means, index)) / Enum.at(scales, index)
        end)
      end)
    end

    {standardize.(oof), standardize.(forecast)}
  end

  defp append_columns(first, second, third) do
    Enum.zip([first, second, third])
    |> Enum.map(fn {left, middle, right} -> left ++ middle ++ right end)
  end

  defp context_matrix(rows) do
    {:ok, contract} = Regional.load_contract()

    divisions =
      contract["population"]["census_divisions"] |> Map.values() |> Enum.uniq() |> Enum.sort()

    Enum.map(rows, fn row ->
      Enum.map([1, 2, 3, 4], &if(row["target_quarter_number"] == &1, do: 1.0, else: 0.0)) ++
        Enum.map(divisions, &if(row["census_division"] == &1, do: 1.0, else: 0.0))
    end)
  end

  @doc false
  @spec trailing_mae_matrix(matrix(), [float()], [String.t()]) :: matrix()
  def trailing_mae_matrix([], [], []), do: []

  def trailing_mae_matrix(predictions, targets, quarter_ids)
      when length(predictions) == length(targets) and length(predictions) == length(quarter_ids) do
    {by_index, _history} =
      quarter_ids
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.reduce({%{}, []}, fn quarter, {by_index, history} ->
        current_indexes =
          quarter_ids
          |> Enum.with_index()
          |> Enum.filter(fn {value, _index} -> value == quarter end)
          |> Enum.map(&elem(&1, 1))

        running =
          if history == [] do
            [1.0, 1.0, 1.0, 1.0]
          else
            column_maes(
              Enum.map(history, &Enum.at(predictions, &1)),
              Enum.map(history, &Enum.at(targets, &1))
            )
          end

        updated = Enum.reduce(current_indexes, by_index, &Map.put(&2, &1, running))
        {updated, history ++ current_indexes}
      end)

    Enum.map(0..(length(predictions) - 1), &Map.fetch!(by_index, &1))
  end

  def trailing_mae_matrix(_predictions, _targets, _quarter_ids),
    do: raise(ArgumentError, "trailing MAE inputs must have equal row counts")

  @spec select_alpha([Regional.row()], [String.t()]) :: float()
  def select_alpha(rows, features) do
    origins = rows |> Enum.map(& &1["forecast_origin"]) |> Enum.uniq() |> Enum.sort()

    scores =
      Enum.reduce(
        origins |> Enum.drop(4) |> Enum.take(-4),
        Map.new(@alphas, &{&1, []}),
        fn validation_origin, scores ->
          inner_train =
            Enum.filter(
              rows,
              &(&1["forecast_origin"] < validation_origin and
                  Date.compare(
                    Date.from_iso8601!(&1["outcome_available_date"]),
                    Regional.quarter_end(validation_origin)
                  ) in [:lt, :eq])
            )

          validation = Enum.filter(rows, &(&1["forecast_origin"] == validation_origin))

          if inner_train |> Enum.map(& &1["forecast_origin"]) |> Enum.uniq() |> length() < 4 do
            scores
          else
            targets = Enum.map(validation, &(&1["target_employment_growth_yoy"] * 1.0))

            Enum.reduce(@alphas, scores, fn alpha, updated ->
              prediction = ridge_predict(inner_train, validation, features, alpha)

              mse =
                Enum.zip(prediction, targets)
                |> Enum.map(fn {left, right} -> :math.pow(left - right, 2) end)
                |> average()

              Map.update!(updated, alpha, &[mse | &1])
            end)
          end
        end
      )

    candidates =
      for alpha <- @alphas, scores[alpha] != [], do: {average(scores[alpha]), -alpha, alpha}

    if candidates == [], do: 100.0, else: candidates |> Enum.min() |> elem(2)
  end

  @spec ridge_predict([Regional.row()], [Regional.row()], [String.t()], float()) :: [float()]
  def ridge_predict(train, forecast, features, alpha) do
    {x_train, x_forecast} = design_matrices(train, forecast, features)
    y = Nx.tensor(Enum.map(train, &(&1["target_employment_growth_yoy"] * 1.0)), type: {:f, 64})
    model = RidgeRegression.fit(x_train, y, alpha: alpha, solver: :cholesky)
    model |> RidgeRegression.predict(x_forecast) |> Nx.to_flat_list()
  end

  defp design_matrices(train, forecast, features) do
    {:ok, contract} = Regional.load_contract()
    states = tl(contract["population"]["state_fips"])

    matrix = fn rows ->
      Enum.map(rows, fn row ->
        Enum.map(features, &(&1 |> then(fn feature -> row[feature] * 1.0 end))) ++
          Enum.map(states, &if(row["state_fips"] == &1, do: 1.0, else: 0.0)) ++
          Enum.map([2, 3, 4], &if(row["target_quarter_number"] == &1, do: 1.0, else: 0.0))
      end)
    end

    train_matrix = matrix.(train)
    forecast_matrix = matrix.(forecast)
    numeric_width = length(features)

    {means, scales} =
      0..(numeric_width - 1)
      |> Enum.map(fn index ->
        values = Enum.map(train_matrix, &Enum.at(&1, index))
        mean = average(values)
        variance = values |> Enum.map(&:math.pow(&1 - mean, 2)) |> average()
        {mean, if(variance == 0.0, do: 1.0, else: :math.sqrt(variance))}
      end)
      |> Enum.unzip()

    standardize = fn rows ->
      Enum.map(rows, fn row ->
        Enum.with_index(row)
        |> Enum.map(fn {value, index} ->
          if index < numeric_width,
            do: (value - Enum.at(means, index)) / Enum.at(scales, index),
            else: value
        end)
      end)
    end

    {Nx.tensor(standardize.(train_matrix), type: {:f, 64}),
     Nx.tensor(standardize.(forecast_matrix), type: {:f, 64})}
  end

  defp column_maes(matrix, targets),
    do:
      matrix
      |> transpose()
      |> Enum.map(fn column ->
        Enum.zip(column, targets)
        |> Enum.map(fn {value, target} -> abs(value - target) end)
        |> average()
      end)

  defp transpose([]), do: []

  defp transpose(rows),
    do:
      rows
      |> hd()
      |> Enum.with_index()
      |> Enum.map(fn {_value, index} -> Enum.map(rows, &Enum.at(&1, index)) end)

  defp dot(values, weights),
    do:
      Enum.zip(values, weights)
      |> Enum.reduce(0.0, fn {value, weight}, sum -> sum + value * weight end)

  defp normalize(values), do: Enum.map(values, &(&1 / Enum.sum(values)))
  defp average(values), do: Enum.sum(values) / length(values)

  defp empirical_radius(predictions, targets) do
    residuals =
      Enum.zip(predictions, targets)
      |> Enum.map(fn {prediction, target} -> abs(prediction - target) end)
      |> Enum.sort()

    if residuals == [] do
      0.0
    else
      index = max(0, ceil(0.8 * length(residuals)) - 1)
      Enum.at(residuals, index)
    end
  end

  defp metrics(predictions) do
    %{
      "overall" => metric_group(predictions),
      "by_forecast_origin" => grouped_metrics(predictions, "forecast_origin"),
      "by_state" => grouped_metrics(predictions, "state_fips"),
      "by_census_division" => grouped_metrics(predictions, "census_division")
    }
  end

  defp grouped_metrics(predictions, field) do
    predictions
    |> Enum.group_by(& &1[field])
    |> Map.new(fn {value, rows} -> {value, metric_group(rows)} end)
  end

  defp metric_group(predictions) do
    predictions
    |> Enum.group_by(& &1["model_id"])
    |> Map.new(fn {model, rows} ->
      errors = Enum.map(rows, & &1["error"])
      absolute = Enum.map(errors, &abs/1)

      coverage =
        Enum.count(
          rows,
          &(&1["final_outcome"] >= &1["interval_lower_80"] and
              &1["final_outcome"] <= &1["interval_upper_80"])
        ) / length(rows)

      median = median(absolute)

      {model,
       %{
         "mae" => average(absolute),
         "rmse" => :math.sqrt(errors |> Enum.map(&:math.pow(&1, 2)) |> average()),
         "median_absolute_error" => median,
         "bias" => average(errors),
         "interval_80_coverage" => coverage,
         "row_count" => length(rows)
       }}
    end)
  end

  defp median(values) do
    sorted = Enum.sort(values)
    count = length(sorted)
    middle = div(count, 2)

    if rem(count, 2) == 0,
      do: (Enum.at(sorted, middle - 1) + Enum.at(sorted, middle)) / 2.0,
      else: Enum.at(sorted, middle)
  end

  defp panel_column_order(_columns) do
    [
      "forecast_origin",
      "state_fips",
      "target_quarter",
      "target_quarter_number",
      "census_division",
      "evaluation_origin",
      "qcew_employment_yoy",
      "qcew_employment_qoq",
      "qcew_employment_yoy_lag1",
      "qcew_establishments_yoy",
      "qcew_total_wages_yoy",
      "bea_real_gdp_yoy",
      "bea_real_gdp_qoq",
      "bea_personal_income_yoy",
      "bea_personal_income_qoq",
      "fhfa_hpi_qoq",
      "fhfa_hpi_yoy",
      "qcew_release_date",
      "bea_release_date",
      "fhfa_release_date",
      "target_employment_growth_yoy",
      "outcome_available_date",
      "target_vintage"
    ]
  end

  defp git_state do
    safe = "safe.directory=#{@repository_root}"
    {head, 0} = System.cmd("git", ["-c", safe, "rev-parse", "HEAD"], cd: @repository_root)

    {status, 0} =
      System.cmd(
        "git",
        ["-c", safe, "status", "--porcelain=v1", "--untracked-files=all"],
        cd: @repository_root
      )

    %{
      "head" => String.trim(head),
      "dirty" => status != "",
      "executable" => System.find_executable("elixir") || ""
    }
  end

  defp sha256(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
end
