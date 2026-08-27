defmodule ElixirDataScience.BLSConformanceReport do
  @moduledoc """
  Builds a runtime-only, language-neutral BLS macro conformance report.

  The report exposes comparison inputs, rules, coverage, handling decisions,
  deterministic clustering settings, and label-independent descriptive output.
  It does not embed available source values or a raw BLS response.
  """

  alias ElixirDataScience.{BLS, BLSMacroExperiment, MacroClustering}

  @default_output_path "artifacts/bls-macro-conformance.json"

  @type report :: %{required(String.t()) => term()}
  @type build_error ::
          {:request_configuration_mismatch, map()}
          | {:source_series_mismatch, map()}
          | {:analysis_observation_mismatch, map()}
          | {:analysis_standardization_mismatch, map()}
          | {:analysis_profile_mismatch, map()}
          | {:clustering_configuration_mismatch, map()}

  @doc "Returns the repository-relative default generated-artifact path."
  @spec default_output_path() :: String.t()
  def default_output_path, do: @default_output_path

  @doc "Builds and validates a conformance report from one completed runtime analysis."
  @spec build(BLS.dataset(), MacroClustering.analysis(), BLSMacroExperiment.configuration()) ::
          {:ok, report()} | {:error, build_error()}
  def build(dataset, analysis, config) do
    with :ok <- validate_request(dataset, config),
         :ok <- validate_series(dataset),
         :ok <- validate_analysis(dataset, analysis),
         :ok <- validate_standardization(analysis),
         :ok <- validate_profiles(analysis),
         :ok <- validate_clustering(analysis, config) do
      {:ok, report(dataset, analysis, config)}
    end
  end

  @doc "Encodes a report as pretty JSON with a trailing newline."
  @spec encode!(report()) :: String.t()
  def encode!(report), do: Jason.encode!(report, pretty: true) <> "\n"

  @doc "Writes a generated report to an explicit path, creating parent directories."
  @spec write(report(), Path.t()) :: :ok | {:error, File.posix()}
  def write(report, output_path) do
    with :ok <- output_path |> Path.dirname() |> File.mkdir_p() do
      File.write(output_path, encode!(report))
    end
  end

  defp report(dataset, analysis, config) do
    contract = BLSMacroExperiment.conformance_contract()
    observations = MacroClustering.observations(dataset)

    %{
      "schema_version" => contract.schema_version,
      "producer" => %{
        "application" => "elixir-data-science",
        "elixir_version" => System.version(),
        "language" => "Elixir",
        "otp_release" => System.otp_release()
      },
      "retrieved_at_utc" => DateTime.to_iso8601(dataset.retrieved_at),
      "artifact_policy" => %{
        "contains_available_source_values" => false,
        "contains_raw_api_response" => false,
        "default_output_path" => @default_output_path,
        "default_output_is_gitignored" => true
      },
      "source" => %{
        "api_messages" => dataset.messages,
        "endpoint" => dataset.source_url,
        "provider" => "U.S. Bureau of Labor Statistics",
        "series" => Enum.map(contract.series, &stringify_keys/1),
        "series_coverage" => source_coverage(dataset)
      },
      "request" => request(dataset),
      "alignment" => alignment(observations),
      "value_handling" => value_handling(dataset, observations, contract),
      "features" => Enum.map(contract.features, &stringify_keys/1),
      "standardization" => standardization(analysis, contract),
      "clustering" => clustering(analysis, config),
      "descriptive_output" => descriptive_output(analysis, contract),
      "comparison" => stringify_keys(contract.comparison)
    }
  end

  defp request(dataset) do
    %{
      "anonymous" => true,
      "end_year" => dataset.end_year,
      "inclusive_year_bounds" => true,
      "series_ids" => BLS.series_ids(),
      "start_year" => dataset.start_year,
      "windows" =>
        Enum.map(dataset.request_windows, fn {start_year, end_year} ->
          %{"end_year" => end_year, "start_year" => start_year}
        end)
    }
  end

  defp source_coverage(dataset) do
    Enum.map(BLS.series_ids(), fn series_id ->
      points = Map.fetch!(dataset.series, series_id)
      unavailable = Map.fetch!(dataset.unavailable, series_id)

      %{
        "available_value_count" => length(points),
        "first_available_month" => points |> List.first() |> point_month(),
        "last_available_month" => points |> List.last() |> point_month(),
        "preliminary_value_count" => Enum.count(points, & &1.preliminary?),
        "series_id" => series_id,
        "unavailable_value_count" => length(unavailable)
      }
    end)
  end

  defp alignment(observations) do
    months = Enum.map(observations, &month(&1.date))

    %{
      "first_month" => List.first(months),
      "join" => "inner join by calendar month after deriving the CPI 12-month change",
      "last_month" => List.last(months),
      "months" => months,
      "observation_count" => length(observations),
      "warmup_months" => 12
    }
  end

  defp value_handling(dataset, observations, contract) do
    unavailable_values =
      for series_id <- BLS.series_ids(),
          point <- Map.fetch!(dataset.unavailable, series_id) do
        %{
          "footnotes" => point.footnotes,
          "month" => month(point.date),
          "series_id" => series_id
        }
      end
      |> Enum.sort_by(&{&1["month"], &1["series_id"]})

    preliminary_values =
      for series_id <- BLS.series_ids(),
          point <- Map.fetch!(dataset.series, series_id),
          point.preliminary? do
        %{"month" => month(point.date), "series_id" => series_id}
      end
      |> Enum.sort_by(&{&1["month"], &1["series_id"]})

    preliminary_aligned_months =
      observations
      |> Enum.filter(& &1.preliminary?)
      |> Enum.map(&month(&1.date))

    %{
      "unavailable" =>
        contract.value_handling.unavailable
        |> stringify_keys()
        |> Map.merge(%{
          "source_value_count" => length(unavailable_values),
          "source_values" => unavailable_values
        }),
      "preliminary" =>
        contract.value_handling.preliminary
        |> stringify_keys()
        |> Map.merge(%{
          "aligned_months" => preliminary_aligned_months,
          "aligned_observation_count" => length(preliminary_aligned_months),
          "source_value_count" => length(preliminary_values),
          "source_values" => preliminary_values
        })
    }
  end

  defp standardization(analysis, contract) do
    summaries = [
      feature_summary("inflation_yoy", analysis.standardization.inflation_yoy),
      feature_summary("unemployment_rate", analysis.standardization.unemployment_rate)
    ]

    contract.standardization
    |> stringify_keys()
    |> Map.put("summaries", summaries)
  end

  defp feature_summary(name, summary) do
    %{
      "mean" => Float.round(summary.mean, 12),
      "name" => name,
      "population_standard_deviation" => Float.round(summary.std, 12)
    }
  end

  defp clustering(analysis, config) do
    %{
      "implementation" => %{
        "input_tensor_type" => "f32",
        "library" => "Scholar.Cluster.KMeans",
        "random_key" => "Nx.Random.key(seed)"
      },
      "runtime" => %{
        "inertia" => Float.round(analysis.inertia, 6),
        "num_iterations" => analysis.num_iterations
      },
      "settings" => cluster_settings(config.cluster_options)
    }
  end

  defp descriptive_output(analysis, contract) do
    assignments =
      analysis.observations
      |> Enum.group_by(&Integer.to_string(&1.cluster), &month(&1.date))

    profiles =
      analysis.profiles
      |> Enum.sort_by(fn profile ->
        {
          profile.mean_inflation_yoy,
          profile.mean_unemployment_rate,
          profile.months,
          profile.first_month,
          profile.last_month,
          Map.fetch!(assignments, profile.cluster)
        }
      end)
      |> Enum.with_index(1)
      |> Enum.map(fn {profile, index} ->
        %{
          "assigned_months" => Map.fetch!(assignments, profile.cluster),
          "comparison_profile_id" => "profile_#{index}",
          "first_assigned_month" => String.slice(profile.first_month, 0, 7),
          "implementation_cluster_id" => profile.cluster,
          "last_assigned_month" => String.slice(profile.last_month, 0, 7),
          "mean_inflation_yoy" => Float.round(profile.mean_inflation_yoy, 6),
          "mean_unemployment_rate" => Float.round(profile.mean_unemployment_rate, 6),
          "months" => profile.months
        }
      end)

    contract.descriptive_output
    |> stringify_keys()
    |> Map.put("profiles", profiles)
  end

  defp validate_request(dataset, config) do
    expected_windows = BLS.year_windows(config.start_year, config.end_year)

    if dataset.start_year == config.start_year and dataset.end_year == config.end_year and
         dataset.request_windows == expected_windows do
      :ok
    else
      {:error,
       {:request_configuration_mismatch,
        %{
          actual_end_year: dataset.end_year,
          actual_start_year: dataset.start_year,
          actual_windows: dataset.request_windows,
          expected_end_year: config.end_year,
          expected_start_year: config.start_year,
          expected_windows: expected_windows
        }}}
    end
  end

  defp validate_series(dataset) do
    expected = Enum.sort(BLS.series_ids())
    actual_series = dataset.series |> Map.keys() |> Enum.sort()
    actual_unavailable = dataset.unavailable |> Map.keys() |> Enum.sort()

    if actual_series == expected and actual_unavailable == expected do
      :ok
    else
      {:error,
       {:source_series_mismatch,
        %{
          actual_series: actual_series,
          actual_unavailable: actual_unavailable,
          expected: expected
        }}}
    end
  end

  defp validate_analysis(dataset, analysis) do
    expected = MacroClustering.observations(dataset)
    actual = Enum.map(analysis.observations, &Map.delete(&1, :cluster))

    if actual == expected do
      :ok
    else
      {:error,
       {:analysis_observation_mismatch,
        %{
          actual_count: length(actual),
          actual_months: Enum.map(actual, &month(&1.date)),
          expected_count: length(expected),
          expected_months: Enum.map(expected, &month(&1.date))
        }}}
    end
  end

  defp validate_clustering(analysis, config) do
    expected = cluster_settings(config.cluster_options)

    actual = %{
      "algorithm" => "k_means",
      "initialization" => Atom.to_string(analysis.init),
      "max_iterations" => analysis.max_iterations,
      "num_clusters" => analysis.num_clusters,
      "num_runs" => analysis.num_runs,
      "seed" => analysis.seed,
      "tolerance" => analysis.tolerance
    }

    if actual == expected do
      :ok
    else
      {:error, {:clustering_configuration_mismatch, %{actual: actual, expected: expected}}}
    end
  end

  defp validate_standardization(analysis) do
    expected = expected_standardization(analysis.observations)

    if analysis.standardization == expected do
      :ok
    else
      {:error,
       {:analysis_standardization_mismatch,
        %{
          actual: analysis.standardization,
          expected: expected
        }}}
    end
  end

  defp validate_profiles(analysis) do
    expected_profiles = expected_profiles(analysis.observations)

    if analysis.profiles == expected_profiles and
         length(expected_profiles) == analysis.num_clusters do
      :ok
    else
      {:error,
       {:analysis_profile_mismatch,
        %{
          actual_profiles: analysis.profiles,
          expected_num_clusters: analysis.num_clusters,
          expected_profiles: expected_profiles
        }}}
    end
  end

  defp expected_profiles(labeled_observations) do
    labeled_observations
    |> Enum.group_by(& &1.cluster)
    |> Enum.map(fn {cluster, rows} ->
      %{
        cluster: Integer.to_string(cluster),
        months: length(rows),
        mean_inflation_yoy: rows |> Enum.map(& &1.inflation_yoy) |> mean(),
        mean_unemployment_rate: rows |> Enum.map(& &1.unemployment_rate) |> mean(),
        first_month:
          rows |> Enum.min_by(& &1.date, Date) |> Map.fetch!(:date) |> Date.to_iso8601(),
        last_month: rows |> Enum.max_by(& &1.date, Date) |> Map.fetch!(:date) |> Date.to_iso8601()
      }
    end)
    |> Enum.sort_by(& &1.cluster)
  end

  defp expected_standardization(observations) do
    %{
      inflation_yoy:
        observations
        |> Enum.map(& &1.inflation_yoy)
        |> feature_statistics(),
      unemployment_rate:
        observations
        |> Enum.map(& &1.unemployment_rate)
        |> feature_statistics()
    }
  end

  defp feature_statistics(values) do
    avg = mean(values)

    variance =
      values
      |> Enum.reduce(0.0, fn value, sum -> sum + :math.pow(value - avg, 2) end)
      |> Kernel./(length(values))

    %{mean: avg, std: :math.sqrt(variance)}
  end

  defp cluster_settings(options) do
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

  defp point_month(nil), do: nil
  defp point_month(point), do: month(point.date)
  defp month(date), do: date |> Date.to_iso8601() |> String.slice(0, 7)
  defp mean(values), do: Enum.sum(values) / length(values)

  defp stringify_keys(value) when is_map(value) do
    Map.new(value, fn {key, nested_value} ->
      {stringify_key(key), stringify_keys(nested_value)}
    end)
  end

  defp stringify_keys(value) when is_list(value), do: Enum.map(value, &stringify_keys/1)
  defp stringify_keys(value), do: value

  defp stringify_key(key) when is_atom(key), do: Atom.to_string(key)
  defp stringify_key(key), do: key
end
