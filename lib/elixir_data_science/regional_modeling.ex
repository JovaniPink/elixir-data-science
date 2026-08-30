defmodule ElixirDataScience.RegionalModeling do
  @moduledoc "Offline ridge experts, expanding backtest, convex stack, and artifact writer."

  alias ElixirDataScience.RegionalExpertEnsemble, as: Regional
  alias Scholar.Linear.RidgeRegression

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
    "alpha"
  ]

  @spec run(Path.t(), Path.t()) :: {:ok, map()} | {:error, term()}
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

        manifest = %{
          "schema_version" => "regional-run-manifest.v1",
          "contract_sha256" => Regional.contract_sha256(),
          "source_bundle_sha256" => sha256(bytes),
          "artifacts" =>
            Map.new(artifacts, fn {name, artifact_bytes} ->
              {name,
               %{"sha256" => sha256(artifact_bytes), "byte_count" => byte_size(artifact_bytes)}}
            end),
          "settings" => %{
            "ridge_solver" => "cholesky",
            "alphas" => @alphas,
            "stack_step" => 0.05,
            "neural_seed" => 42
          },
          "metrics" => metrics(predictions),
          "exclusions" => elem(Regional.load_contract(), 1)["excluded_v1"],
          "claims" => %{
            "description" => "point-in-time historical backtest",
            "causal" => false,
            "recession" => false,
            "trading" => false,
            "financial_advice" => false
          }
        }

        File.write!(
          Path.join(output_dir, "regional-run-manifest.v1.json"),
          Jason.encode!(manifest) <> "\n"
        )

        {:ok, manifest}
      end
    end
  end

  @spec backtest([map()], [map()]) :: [map()]
  def backtest(panel, folds) do
    panel_by_key = Map.new(panel, &{{&1["forecast_origin"], &1["state_fips"]}, &1})
    {all_oof_rows, all_oof_matrix, all_oof_targets} = oof_predictions(panel)

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

      {oof_rows, oof_matrix, oof_targets} =
        Enum.zip([all_oof_rows, all_oof_matrix, all_oof_targets])
        |> Enum.filter(fn {row, _prediction, _target} ->
          row["forecast_origin"] < outer_origin and
            Date.compare(
              Date.from_iso8601!(row["outcome_available_date"]),
              Regional.quarter_end(outer_origin)
            ) in [:lt, :eq]
        end)
        |> Enum.reduce({[], [], []}, fn {row, prediction, target}, {rows, matrix, targets} ->
          {[row | rows], [prediction | matrix], [target | targets]}
        end)
        |> then(fn {rows, matrix, targets} ->
          {Enum.reverse(rows), Enum.reverse(matrix), Enum.reverse(targets)}
        end)

      {stack_weights, inverse_weights, radius} =
        if oof_rows == [] do
          weights = [0.25, 0.25, 0.25, 0.25]
          {weights, weights, 0.0}
        else
          stack = Regional.search_convex_stack(oof_matrix, oof_targets)
          maes = column_maes(oof_matrix, oof_targets)
          inverse = normalize(Enum.map(maes, &(1.0 / max(&1, 1.0e-12))))

          residuals =
            Enum.zip(oof_matrix, oof_targets)
            |> Enum.map(fn {row, target} -> abs(dot(row, stack) - target) end)

          {stack, inverse, quantile(residuals, 0.8)}
        end

      equal = Enum.map(forecast_matrix, &(Enum.sum(&1) / 4.0))
      inverse = Enum.map(forecast_matrix, &dot(&1, inverse_weights))
      stack = Enum.map(forecast_matrix, &dot(&1, stack_weights))

      models = [
        {"zero", List.duplicate(0.0, length(forecast)), nil, ""},
        {"latest_qcew_yoy", Enum.map(forecast, &(&1["qcew_employment_yoy"] * 1.0)), nil, ""},
        {"pooled_ridge", pooled, nil, pooled_alpha},
        {"equal_weight", equal, [0.25, 0.25, 0.25, 0.25], ""},
        {"inverse_mae", inverse, inverse_weights, ""},
        {"convex_stack", stack, stack_weights, ""}
      ]

      models =
        if oof_rows |> Enum.map(& &1["forecast_origin"]) |> Enum.uniq() |> length() >= 8 do
          {neural_predictions, neural_weights} =
            neural_gate(oof_rows, oof_matrix, oof_targets, forecast, forecast_matrix)

          models ++ [{"neural_gate", neural_predictions, neural_weights, ""}]
        else
          models
        end

      Enum.with_index(forecast)
      |> Enum.flat_map(fn {row, index} ->
        outcome = row["target_employment_growth_yoy"] * 1.0

        Enum.map(models, fn {model_id, values, weights, alpha} ->
          prediction = Enum.at(values, index)
          weights = row_weights(weights, index)

          %{
            "forecast_origin" => outer_origin,
            "state_fips" => row["state_fips"],
            "target_quarter" => row["target_quarter"],
            "census_division" => row["census_division"],
            "model_id" => model_id,
            "prediction" => prediction,
            "final_outcome" => outcome,
            "error" => prediction - outcome,
            "interval_lower_80" => prediction - radius,
            "interval_upper_80" => prediction + radius,
            "weight_labor" => Enum.at(weights, 0),
            "weight_business" => Enum.at(weights, 1),
            "weight_growth" => Enum.at(weights, 2),
            "weight_housing" => Enum.at(weights, 3),
            "alpha" => alpha
          }
        end)
      end)
    end)
    |> Enum.sort_by(&{&1["forecast_origin"], &1["state_fips"], &1["model_id"]})
  end

  defp oof_predictions(train) do
    train
    |> Enum.map(& &1["forecast_origin"])
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.reduce({[], [], []}, fn origin, {rows_acc, predictions_acc, targets_acc} ->
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
        {rows_acc, predictions_acc, targets_acc}
      else
        validation = Enum.filter(train, &(&1["forecast_origin"] == origin))

        columns =
          Enum.map(@experts, fn {_expert, features} ->
            ridge_predict(prior, validation, features, select_alpha(prior, features))
          end)

        {rows_acc ++ validation, predictions_acc ++ transpose(columns),
         targets_acc ++ Enum.map(validation, &(&1["target_employment_growth_yoy"] * 1.0))}
      end
    end)
  end

  defp row_weights(nil, _index), do: ["", "", "", ""]

  defp row_weights([first | _rest] = weights, index) when is_list(first),
    do: Enum.at(weights, index)

  defp row_weights(weights, _index), do: weights

  defp neural_gate(oof_rows, oof_matrix, oof_targets, forecast, forecast_matrix) do
    trailing = trailing_mae_matrix(oof_matrix, oof_targets)
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
      |> Axon.Loop.run(train_data, %{}, epochs: 500, iterations: 1)

    inputs = %{
      "gate_input" => Nx.tensor(standardized_forecast, type: {:f, 32}),
      "experts" => Nx.tensor(forecast_matrix, type: {:f, 32})
    }

    predictions = prediction_model |> Axon.predict(model_state, inputs) |> Nx.to_flat_list()
    weights = weights_model |> Axon.predict(model_state, inputs) |> Nx.to_list()
    {predictions, weights}
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

  defp trailing_mae_matrix(predictions, targets) do
    predictions
    |> Enum.with_index()
    |> Enum.map(fn {_row, index} ->
      if index == 0,
        do: [1.0, 1.0, 1.0, 1.0],
        else: column_maes(Enum.take(predictions, index), Enum.take(targets, index))
    end)
  end

  @spec select_alpha([map()], [String.t()]) :: float()
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

  @spec ridge_predict([map()], [map()], [String.t()], float()) :: [float()]
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

  defp quantile(values, quantile),
    do: values |> Enum.sort() |> Enum.at(round((length(values) - 1) * quantile))

  defp metrics(predictions) do
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

      sorted = Enum.sort(absolute)
      median = Enum.at(sorted, div(length(sorted) - 1, 2))

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

  defp sha256(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
end
