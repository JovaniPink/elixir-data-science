defmodule ElixirDataScience.BLSConformanceReport do
  @moduledoc """
  Builds a portable, label-independent BLS macro comparison report.

  The report contains source and transformation metadata, aligned month
  identities, standardized feature summaries, and descriptive cluster output.
  It deliberately excludes available source values and raw API responses.
  """

  alias ElixirDataScience.{BLS, BLSMacroExperiment, MacroClustering}

  @type json_value ::
          nil
          | boolean()
          | number()
          | String.t()
          | [json_value()]
          | %{optional(String.t()) => json_value()}

  @type report :: %{required(String.t()) => json_value()}

  @type build_error ::
          {:request_configuration_mismatch, map()}
          | {:source_configuration_mismatch, map()}
          | {:analysis_configuration_mismatch, map()}
          | :analysis_observations_mismatch
          | {:invalid_cluster_labels, [term()]}

  @doc "Builds a versioned comparison report from one fetched and clustered dataset."
  @spec build(BLS.dataset(), MacroClustering.analysis(), BLSMacroExperiment.configuration()) ::
          {:ok, report()} | {:error, build_error()}
  def build(dataset, analysis, config) do
    with :ok <- validate_request(dataset, config),
         :ok <- validate_source(dataset),
         :ok <- validate_analysis_configuration(analysis, config),
         :ok <- validate_observations(dataset, analysis),
         :ok <- validate_cluster_labels(analysis) do
      {:ok, build_report(dataset, analysis, config)}
    end
  end

  @doc "Encodes a report as formatted JSON with a final newline."
  @spec encode!(report()) :: String.t()
  def encode!(report), do: Jason.encode!(report, pretty: true) <> "\n"

  @doc "Writes a report atomically to an explicit generated-artifact path."
  @spec write(report(), Path.t()) :: :ok | {:error, File.posix() | :badarg}
  def write(report, path) when is_binary(path) and byte_size(path) > 0 do
    File.mkdir_p!(Path.dirname(path))
    temporary_path = path <> ".tmp-#{System.unique_integer([:positive, :monotonic])}"

    result =
      with :ok <- File.write(temporary_path, encode!(report), [:binary]),
           :ok <- File.rename(temporary_path, path) do
        :ok
      end

    if result != :ok, do: File.rm(temporary_path)
    result
  end

  def write(_report, _path), do: {:error, :badarg}

  defp validate_request(dataset, config) do
    expected_windows = BLS.year_windows(config.start_year, config.end_year)

    actual_request_mode = Map.get(dataset, :request_mode, :unknown)

    if dataset.start_year == config.start_year and dataset.end_year == config.end_year and
         dataset.request_windows == expected_windows and actual_request_mode == :anonymous do
      :ok
    else
      {:error,
       {:request_configuration_mismatch,
        %{
          actual_start_year: dataset.start_year,
          expected_start_year: config.start_year,
          actual_end_year: dataset.end_year,
          expected_end_year: config.end_year,
          actual_windows: dataset.request_windows,
          expected_windows: expected_windows,
          actual_request_mode: actual_request_mode,
          expected_request_mode: :anonymous
        }}}
    end
  end

  defp validate_source(dataset) do
    actual_series_ids = dataset.series |> Map.keys() |> Enum.sort()
    actual_unavailable_series_ids = dataset.unavailable |> Map.keys() |> Enum.sort()
    expected_series_ids = Enum.sort(BLS.series_ids())

    if dataset.source_url == BLS.endpoint() and actual_series_ids == expected_series_ids and
         actual_unavailable_series_ids == expected_series_ids do
      :ok
    else
      {:error,
       {:source_configuration_mismatch,
        %{
          actual_source_url: dataset.source_url,
          expected_source_url: BLS.endpoint(),
          actual_series_ids: actual_series_ids,
          expected_series_ids: expected_series_ids,
          actual_unavailable_series_ids: actual_unavailable_series_ids
        }}}
    end
  end

  defp validate_analysis_configuration(analysis, config) do
    expected = clustering_settings(config.cluster_options)

    actual = %{
      "initialization" => Atom.to_string(analysis.init),
      "max_iterations" => analysis.max_iterations,
      "num_clusters" => analysis.num_clusters,
      "num_runs" => analysis.num_runs,
      "seed" => analysis.seed,
      "tolerance" => analysis.tolerance
    }

    if actual == Map.delete(expected, "algorithm") do
      :ok
    else
      {:error, {:analysis_configuration_mismatch, %{actual: actual, expected: expected}}}
    end
  end

  defp validate_observations(dataset, analysis) do
    expected = MacroClustering.observations(dataset)

    actual =
      Enum.map(analysis.observations, fn observation ->
        Map.take(observation, [:date, :inflation_yoy, :unemployment_rate, :preliminary?])
      end)

    if actual == expected, do: :ok, else: {:error, :analysis_observations_mismatch}
  end

  defp validate_cluster_labels(analysis) do
    invalid =
      analysis.observations
      |> Enum.map(& &1.cluster)
      |> Enum.reject(&(is_integer(&1) and &1 >= 0 and &1 < analysis.num_clusters))
      |> Enum.uniq()

    if invalid == [], do: :ok, else: {:error, {:invalid_cluster_labels, invalid}}
  end

  defp build_report(dataset, analysis, config) do
    contract = BLSMacroExperiment.conformance_contract()
    observations = Enum.sort_by(analysis.observations, & &1.date, Date)
    unavailable = unavailable_values(dataset)
    preliminary_source = preliminary_source_values(dataset)
    preliminary_aligned = Enum.filter(observations, & &1.preliminary?)

    %{
      "schema_version" => contract.schema_version,
      "producer" => %{
        "language" => "Elixir",
        "elixir_version" => System.version(),
        "otp_version" => to_string(:erlang.system_info(:otp_release)),
        "scholar_version" => application_version(:scholar)
      },
      "source" => %{
        "publisher" => "U.S. Bureau of Labor Statistics",
        "source_url" => dataset.source_url,
        "retrieved_at" => DateTime.to_iso8601(dataset.retrieved_at),
        "series_ids" => BLS.series_ids(),
        "api_messages" => dataset.messages
      },
      "request" => %{
        "anonymous" => dataset.request_mode == :anonymous,
        "start_year" => config.start_year,
        "end_year" => config.end_year,
        "inclusive_year_bounds" => true,
        "series_ids" => BLS.series_ids(),
        "windows" =>
          Enum.map(dataset.request_windows, fn {start_year, end_year} ->
            %{"start_year" => start_year, "end_year" => end_year}
          end)
      },
      "features" => stringify_keys(contract.features),
      "standardization" =>
        contract.standardization
        |> stringify_keys()
        |> Map.put("feature_statistics", feature_statistics(analysis.standardization)),
      "value_handling" => %{
        "unavailable" => %{
          "policy" => contract.value_handling.unavailable.policy,
          "source_value_count" => length(unavailable),
          "source_values" => unavailable
        },
        "preliminary" => %{
          "propagation_inputs" => contract.value_handling.preliminary.propagation_inputs,
          "source_value_count" => length(preliminary_source),
          "source_values" => preliminary_source,
          "aligned_observation_count" => length(preliminary_aligned),
          "aligned_months" => Enum.map(preliminary_aligned, &month(&1.date))
        }
      },
      "alignment" => %{
        "observation_count" => length(observations),
        "first_month" => observations |> List.first() |> Map.fetch!(:date) |> month(),
        "last_month" => observations |> List.last() |> Map.fetch!(:date) |> month(),
        "months" => Enum.map(observations, &month(&1.date))
      },
      "clustering" => %{
        "settings" => clustering_settings(config.cluster_options),
        "result" => %{
          "inertia" => analysis.inertia,
          "num_iterations" => analysis.num_iterations
        }
      },
      "comparison" => stringify_keys(contract.comparison),
      "descriptive_output" => %{
        "profiles" => comparison_profiles(observations)
      },
      "claims" => %{
        "causal" => false,
        "predictive" => false,
        "recession" => false,
        "financial" => false
      }
    }
  end

  defp clustering_settings(options) do
    %{
      "algorithm" => "k_means",
      "initialization" => options |> Keyword.fetch!(:init) |> Atom.to_string(),
      "max_iterations" => Keyword.fetch!(options, :max_iterations),
      "num_clusters" => Keyword.fetch!(options, :num_clusters),
      "num_runs" => Keyword.fetch!(options, :num_runs),
      "seed" => Keyword.fetch!(options, :seed),
      "tolerance" => Keyword.fetch!(options, :tolerance)
    }
  end

  defp unavailable_values(dataset) do
    dataset.unavailable
    |> Enum.flat_map(fn {series_id, points} ->
      Enum.map(points, fn point ->
        %{
          "series_id" => series_id,
          "month" => month(point.date),
          "source_value" => point.value,
          "footnotes" => point.footnotes
        }
      end)
    end)
    |> Enum.sort_by(&{&1["month"], &1["series_id"]})
  end

  defp preliminary_source_values(dataset) do
    dataset.series
    |> Enum.flat_map(fn {series_id, points} ->
      points
      |> Enum.filter(& &1.preliminary?)
      |> Enum.map(fn point ->
        %{"series_id" => series_id, "month" => month(point.date)}
      end)
    end)
    |> Enum.sort_by(&{&1["month"], &1["series_id"]})
  end

  defp feature_statistics(standardization) do
    [
      feature_statistic("inflation_yoy", standardization.inflation_yoy),
      feature_statistic("unemployment_rate", standardization.unemployment_rate)
    ]
  end

  defp feature_statistic(name, summary) do
    %{
      "name" => name,
      "population_mean" => summary.mean,
      "population_standard_deviation" => summary.std
    }
  end

  defp comparison_profiles(observations) do
    observations
    |> Enum.group_by(& &1.cluster)
    |> Enum.map(fn {_cluster, rows} ->
      assigned_months = rows |> Enum.map(&month(&1.date)) |> Enum.sort()

      %{
        assigned_months: assigned_months,
        months: length(rows),
        mean_inflation_yoy: rows |> Enum.map(& &1.inflation_yoy) |> mean(),
        mean_unemployment_rate: rows |> Enum.map(& &1.unemployment_rate) |> mean(),
        first_month: List.first(assigned_months),
        last_month: List.last(assigned_months)
      }
    end)
    |> Enum.sort_by(fn profile ->
      {
        profile.mean_inflation_yoy,
        profile.mean_unemployment_rate,
        profile.first_month,
        profile.assigned_months
      }
    end)
    |> Enum.with_index(1)
    |> Enum.map(fn {profile, index} ->
      %{
        "comparison_profile_id" => "profile_#{index}",
        "assigned_months" => profile.assigned_months,
        "months" => profile.months,
        "mean_inflation_yoy" => profile.mean_inflation_yoy,
        "mean_unemployment_rate" => profile.mean_unemployment_rate,
        "first_month" => profile.first_month,
        "last_month" => profile.last_month
      }
    end)
  end

  defp stringify_keys(value) when is_list(value), do: Enum.map(value, &stringify_keys/1)

  defp stringify_keys(value) when is_map(value) do
    Map.new(value, fn {key, nested} ->
      key = if is_atom(key), do: Atom.to_string(key), else: key
      {key, stringify_keys(nested)}
    end)
  end

  defp stringify_keys(value), do: value

  defp month(date), do: Calendar.strftime(date, "%Y-%m")
  defp mean(values), do: Enum.sum(values) / length(values)

  defp application_version(application) do
    case Application.spec(application, :vsn) do
      nil -> "unavailable"
      version -> to_string(version)
    end
  end
end
