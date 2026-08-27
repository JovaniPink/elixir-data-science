defmodule ElixirDataScience.MacroClustering do
  @moduledoc """
  Derives monthly macroeconomic observations and applies descriptive K-means.

  Cluster identifiers are arbitrary labels. The output describes combinations
  observed in the selected sample; it does not estimate causality, predict a
  recession, or provide an investment signal.
  """

  alias Scholar.Cluster.KMeans

  @cpi_series "CUUR0000SA0"
  @unemployment_series "LNS14000000"

  @type observation :: %{
          date: Date.t(),
          inflation_yoy: float(),
          unemployment_rate: float(),
          preliminary?: boolean()
        }

  @type labeled_observation :: %{
          date: Date.t(),
          inflation_yoy: float(),
          unemployment_rate: float(),
          preliminary?: boolean(),
          cluster: non_neg_integer()
        }

  @type cluster_option ::
          {:num_clusters, pos_integer()}
          | {:seed, integer()}
          | {:num_runs, pos_integer()}
          | {:init, :k_means_plus_plus | :random}
          | {:max_iterations, pos_integer()}
          | {:tolerance, float()}

  @type feature_summary :: %{mean: float(), std: float()}

  @type standardization :: %{
          inflation_yoy: feature_summary(),
          unemployment_rate: feature_summary()
        }

  @type cluster_profile :: %{
          cluster: String.t(),
          months: pos_integer(),
          mean_inflation_yoy: float(),
          mean_unemployment_rate: float(),
          first_month: String.t(),
          last_month: String.t()
        }

  @type kmeans_model :: %KMeans{
          num_iterations: Nx.Tensor.t(),
          clusters: Nx.Tensor.t(),
          inertia: Nx.Tensor.t(),
          labels: Nx.Tensor.t()
        }

  @type analysis :: %{
          observations: [labeled_observation()],
          profiles: [cluster_profile()],
          standardization: standardization(),
          num_clusters: pos_integer(),
          seed: integer(),
          num_runs: pos_integer(),
          init: :k_means_plus_plus | :random,
          max_iterations: pos_integer(),
          tolerance: float(),
          inertia: float(),
          num_iterations: non_neg_integer(),
          model: kmeans_model()
        }

  @type cluster_error :: :constant_feature | {:invalid_cluster_request, non_neg_integer(), term()}

  @doc """
  Aligns CPI-U and unemployment by month and computes 12-month CPI inflation.

  The first 12 months are intentionally omitted because no in-sample CPI lag
  is available for them.
  """
  @spec observations(ElixirDataScience.BLS.dataset()) :: [observation()]
  def observations(%{series: series}) do
    cpi = series |> Map.get(@cpi_series, []) |> point_index()
    unemployment = series |> Map.get(@unemployment_series, []) |> point_index()

    cpi
    |> Map.values()
    |> Enum.sort_by(& &1.date, Date)
    |> Enum.flat_map(fn current_cpi ->
      prior_date = Date.new!(current_cpi.date.year - 1, current_cpi.date.month, 1)

      with %{value: prior_cpi} = previous_cpi <- Map.get(cpi, prior_date),
           %{value: unemployment_rate} = current_unemployment <-
             Map.get(unemployment, current_cpi.date) do
        [
          %{
            date: current_cpi.date,
            inflation_yoy: (current_cpi.value / prior_cpi - 1.0) * 100.0,
            unemployment_rate: unemployment_rate,
            preliminary?:
              current_cpi.preliminary? or previous_cpi.preliminary? or
                current_unemployment.preliminary?
          }
        ]
      else
        _ -> []
      end
    end)
  end

  @doc """
  Standardizes inflation and unemployment, then fits deterministic K-means.

  Options:

    * `:num_clusters` - defaults to 3
    * `:seed` - defaults to 42
    * `:num_runs` - defaults to 20
    * `:init` - defaults to `:k_means_plus_plus`
    * `:max_iterations` - defaults to 300
    * `:tolerance` - defaults to `1.0e-4`

  """
  @spec cluster([observation()], [cluster_option()]) ::
          {:ok, analysis()} | {:error, cluster_error()}
  def cluster(observations, opts \\ []) when is_list(observations) do
    num_clusters = Keyword.get(opts, :num_clusters, 3)
    seed = Keyword.get(opts, :seed, 42)
    num_runs = Keyword.get(opts, :num_runs, 20)
    init = Keyword.get(opts, :init, :k_means_plus_plus)
    max_iterations = Keyword.get(opts, :max_iterations, 300)
    tolerance = Keyword.get(opts, :tolerance, 1.0e-4)

    with :ok <-
           validate_cluster_request(
             observations,
             num_clusters,
             seed,
             num_runs,
             init,
             max_iterations,
             tolerance
           ),
         {:ok, standardized, standardization} <- standardize(observations) do
      tensor = Nx.tensor(standardized, type: :f32)

      model =
        KMeans.fit(tensor,
          num_clusters: num_clusters,
          num_runs: num_runs,
          init: init,
          max_iterations: max_iterations,
          tol: tolerance,
          key: Nx.Random.key(seed)
        )

      labels = Nx.to_flat_list(model.labels)

      labeled_observations =
        observations
        |> Enum.zip(labels)
        |> Enum.map(fn {observation, label} -> Map.put(observation, :cluster, label) end)

      {:ok,
       %{
         observations: labeled_observations,
         profiles: cluster_profiles(labeled_observations),
         standardization: standardization,
         num_clusters: num_clusters,
         seed: seed,
         num_runs: num_runs,
         init: init,
         max_iterations: max_iterations,
         tolerance: tolerance,
         inertia: Nx.to_number(model.inertia),
         num_iterations: Nx.to_number(model.num_iterations),
         model: model
       }}
    end
  end

  @doc "Converts labeled observations to an Explorer dataframe for inspection."
  @spec to_dataframe(analysis()) :: Explorer.DataFrame.t()
  def to_dataframe(%{observations: observations}) do
    observations
    |> Enum.map(fn observation ->
      observation
      |> Map.update!(:date, &Date.to_iso8601/1)
      |> Map.update!(:cluster, &Integer.to_string/1)
    end)
    |> Explorer.DataFrame.new()
  end

  @doc "Converts cluster profiles to an Explorer dataframe."
  @spec profiles_dataframe(analysis()) :: Explorer.DataFrame.t()
  def profiles_dataframe(%{profiles: profiles}), do: Explorer.DataFrame.new(profiles)

  defp point_index(points), do: Map.new(points, &{&1.date, &1})

  defp standardize(observations) do
    rows = Enum.map(observations, &[&1.inflation_yoy, &1.unemployment_rate])
    columns = transpose(rows)
    means = Enum.map(columns, &mean/1)

    standard_deviations =
      Enum.map(Enum.zip(columns, means), fn {column, avg} -> std(column, avg) end)

    if Enum.any?(standard_deviations, &(&1 == 0.0)) do
      {:error, :constant_feature}
    else
      standardized =
        Enum.map(rows, fn row ->
          row
          |> Enum.zip(means)
          |> Enum.zip(standard_deviations)
          |> Enum.map(fn {{value, avg}, deviation} -> (value - avg) / deviation end)
        end)

      {:ok, standardized,
       %{
         inflation_yoy: %{mean: Enum.at(means, 0), std: Enum.at(standard_deviations, 0)},
         unemployment_rate: %{mean: Enum.at(means, 1), std: Enum.at(standard_deviations, 1)}
       }}
    end
  end

  defp cluster_profiles(labeled_observations) do
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

  defp validate_cluster_request(
         observations,
         num_clusters,
         seed,
         num_runs,
         init,
         max_iterations,
         tolerance
       )
       when is_integer(num_clusters) and num_clusters > 1 and
              length(observations) >= num_clusters and is_integer(seed) and
              is_integer(num_runs) and num_runs > 0 and
              init in [:k_means_plus_plus, :random] and is_integer(max_iterations) and
              max_iterations > 0 and is_float(tolerance) and tolerance > 0.0,
       do: :ok

  defp validate_cluster_request(observations, num_clusters, _seed, _num_runs, _init, _max, _tol),
    do: {:error, {:invalid_cluster_request, length(observations), num_clusters}}

  defp transpose(rows), do: rows |> Enum.zip() |> Enum.map(&Tuple.to_list/1)
  defp mean(values), do: Enum.sum(values) / length(values)

  defp std(values, avg) do
    values
    |> Enum.reduce(0.0, fn value, sum -> sum + :math.pow(value - avg, 2) end)
    |> Kernel./(length(values))
    |> :math.sqrt()
  end
end
