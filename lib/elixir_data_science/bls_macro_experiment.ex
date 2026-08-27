defmodule ElixirDataScience.BLSMacroExperiment do
  @moduledoc "Typed configuration for the BLS macro clustering experiment."

  alias ElixirDataScience.MacroClustering

  @type configuration :: %{
          start_year: pos_integer(),
          end_year: pos_integer(),
          cluster_options: [MacroClustering.cluster_option()]
        }

  @type conformance_contract :: %{
          schema_version: String.t(),
          series: [map()],
          features: [map()],
          standardization: map(),
          value_handling: map(),
          descriptive_output: map(),
          comparison: map()
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

  @doc "Returns the language-neutral contract emitted in conformance reports."
  @spec conformance_contract() :: conformance_contract()
  def conformance_contract do
    %{
      schema_version: "bls-macro-conformance.v1",
      series: [
        %{
          id: "CUUR0000SA0",
          measure: "CPI-U, U.S. city average, all items",
          frequency: "monthly",
          seasonal_adjustment: "not_seasonally_adjusted",
          role: "current and 12-month-lag CPI index values"
        },
        %{
          id: "LNS14000000",
          measure: "civilian unemployment rate",
          frequency: "monthly",
          seasonal_adjustment: "seasonally_adjusted",
          role: "current unemployment-rate level"
        }
      ],
      features: [
        %{
          name: "inflation_yoy",
          source_series_ids: ["CUUR0000SA0"],
          definition: "((current_cpi / cpi_12_month_lag) - 1) * 100",
          lag_months: 12,
          unit: "percent"
        },
        %{
          name: "unemployment_rate",
          source_series_ids: ["LNS14000000"],
          definition: "published monthly value",
          lag_months: 0,
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
          detection: "BLS footnote code P or footnote text containing the word Preliminary",
          propagation: "logical OR across every source value used by an observation",
          propagation_inputs: [
            "current_cpi",
            "cpi_12_month_lag",
            "current_unemployment"
          ]
        }
      },
      descriptive_output: %{
        claim_boundary:
          "ex-post descriptive output; not causal, predictive, a recession classifier, " <>
            "a trading signal, or financial advice",
        cluster_ids_arbitrary: true,
        profile_order:
          "ascending mean_inflation_yoy, then mean_unemployment_rate, month count, " <>
            "first month, last month, and lexicographic assigned-month list",
        numeric_precision_decimal_places: 6
      },
      comparison: %{
        exact_fields: [
          "request",
          "source.endpoint",
          "source.series",
          "source.series_coverage",
          "alignment.months",
          "value_handling",
          "features",
          "standardization.method",
          "standardization.formula",
          "standardization.degrees_of_freedom",
          "clustering.settings",
          "descriptive_output.profiles[].assigned_months"
        ],
        numeric_fields: [
          "standardization.summaries[].mean",
          "standardization.summaries[].population_standard_deviation",
          "descriptive_output.profiles[].mean_inflation_yoy",
          "descriptive_output.profiles[].mean_unemployment_rate"
        ],
        numeric_tolerance: 1.0e-6,
        informational_fields: [
          "producer",
          "retrieved_at_utc",
          "source.api_messages",
          "clustering.implementation",
          "clustering.runtime",
          "descriptive_output.profiles[].implementation_cluster_id"
        ]
      }
    }
  end
end
