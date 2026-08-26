defmodule ElixirDataScience.BLSMacroExperiment do
  @moduledoc "Typed configuration for the BLS macro clustering experiment."

  alias ElixirDataScience.MacroClustering

  @type configuration :: %{
          start_year: pos_integer(),
          end_year: pos_integer(),
          cluster_options: [MacroClustering.cluster_option()]
        }

  @doc "Returns the fixed source and clustering configuration."
  @spec configuration() :: configuration()
  def configuration do
    %{
      start_year: 2006,
      end_year: 2026,
      cluster_options: [num_clusters: 3, seed: 42, num_runs: 20]
    }
  end
end
