defmodule ElixirDataScience.BLSMacroExperiment do
  @moduledoc "Typed configuration for the BLS macro clustering experiment."

  alias ElixirDataScience.MacroClustering

  @type configuration :: %{
          start_year: pos_integer(),
          end_year: pos_integer(),
          cluster_options: [MacroClustering.cluster_option()]
        }

  @type feature_contract :: %{
          name: String.t(),
          source_series_ids: [String.t()],
          transformation: String.t(),
          unit: String.t()
        }

  @type conformance_contract :: %{
          schema_version: String.t(),
          features: [feature_contract()],
          standardization: %{
            method: String.t(),
            formula: String.t(),
            degrees_of_freedom: non_neg_integer()
          },
          value_handling: %{
            unavailable: %{policy: String.t()},
            preliminary: %{propagation_inputs: [String.t()]}
          },
          comparison: %{
            cluster_labels: String.t(),
            profile_order: String.t(),
            floating_point_tolerance: float()
          }
        }

  @doc "Returns the fixed source and clustering configuration."
  @spec configuration() :: configuration()
  def configuration do
    %{
      start_year: 2006,
      end_year: 2026,
      cluster_options: [
        num_clusters: 3,
        seed: 42,
        num_runs: 20,
        init: :k_means_plus_plus,
        max_iterations: 300,
        tolerance: 1.0e-4
      ]
    }
  end

  @doc "Returns the versioned, language-neutral comparison contract."
  @spec conformance_contract() :: conformance_contract()
  def conformance_contract do
    %{
      schema_version: "bls-macro-conformance.v1",
      features: [
        %{
          name: "inflation_yoy",
          source_series_ids: ["CUUR0000SA0"],
          transformation: "(current_cpi / cpi_12_month_lag - 1) * 100",
          unit: "percent"
        },
        %{
          name: "unemployment_rate",
          source_series_ids: ["LNS14000000"],
          transformation: "published monthly value",
          unit: "percent"
        }
      ],
      standardization: %{
        method: "population_z_score",
        formula: "(value - population_mean) / population_standard_deviation",
        degrees_of_freedom: 0
      },
      value_handling: %{
        unavailable: %{
          policy: "retain source metadata, exclude from alignment, and do not impute"
        },
        preliminary: %{
          propagation_inputs: [
            "current_cpi",
            "cpi_12_month_lag",
            "current_unemployment"
          ]
        }
      },
      comparison: %{
        cluster_labels: "arbitrary and excluded from profile identity",
        profile_order: "mean_inflation_yoy, mean_unemployment_rate, first_month, assigned_months",
        floating_point_tolerance: 1.0e-6
      }
    }
  end
end
