defmodule ElixirDataScience.QCEWComparison do
  @moduledoc """
  Reproducible QCEW download, grouping, and measurement experiment.

  The committed code defines the comparison contract. Source CSV files,
  derived CSV files, and emitted manifests stay in ignored directories.
  """

  alias Explorer.{DataFrame, Series}

  require DataFrame

  @schema_version "qcew-comparison-manifest.v1"
  @source_metadata_version "qcew-source-metadata.v1"
  @experiment_id "qcew-2024-q1-county-total-by-state"
  @source_url "https://data.bls.gov/cew/data/api/2024/1/industry/10.csv"
  @year 2024
  @quarter 1
  @default_iterations 5
  @default_source_path "data/qcew/2024-q1-industry-10.csv"
  @default_output_dir "artifacts/qcew-comparison/v1"
  @result_filename "qcew-state-totals.v1.csv"
  @manifest_filename "qcew-comparison-manifest.v1.json"

  @id_columns [
    "area_fips",
    "own_code",
    "industry_code",
    "agglvl_code",
    "size_code",
    "year",
    "qtr",
    "disclosure_code"
  ]

  @measure_columns [
    "qtrly_estabs",
    "month1_emplvl",
    "month2_emplvl",
    "month3_emplvl",
    "total_qtrly_wages"
  ]

  @input_columns @id_columns ++ @measure_columns
  @output_columns [
    "state_fips",
    "county_rows",
    "qtrly_estabs",
    "month1_emplvl",
    "month2_emplvl",
    "month3_emplvl",
    "total_qtrly_wages"
  ]

  @type configuration :: %{
          schema_version: String.t(),
          experiment_id: String.t(),
          source_url: String.t(),
          year: pos_integer(),
          quarter: 1..4,
          filters: %{required(String.t()) => String.t()},
          grouping_key: String.t(),
          input_columns: [String.t()],
          output_columns: [String.t()]
        }

  @type transform_result :: %{
          csv: String.t(),
          sha256: String.t(),
          source_row_count: non_neg_integer(),
          selected_row_count: non_neg_integer(),
          output_row_count: non_neg_integer(),
          totals: %{required(String.t()) => integer()}
        }

  @type json_value ::
          nil
          | boolean()
          | number()
          | String.t()
          | [json_value()]
          | %{optional(String.t()) => json_value()}

  @type manifest :: %{required(String.t()) => json_value()}

  @type execution :: %{
          result_path: Path.t(),
          manifest_path: Path.t(),
          manifest: manifest()
        }

  @type memory_sample :: %{
          required(String.t()) => non_neg_integer() | nil
        }

  @type run_option ::
          {:source_path, Path.t()}
          | {:output_dir, Path.t()}
          | {:iterations, pos_integer()}
          | {:refresh_source, boolean()}
          | {:host_hardware_label, String.t()}
          | {:host_cpu_model, String.t()}
          | {:host_logical_processors, pos_integer()}
          | {:host_memory_bytes, pos_integer()}
          | {:download_fun, (String.t(), Path.t() -> :ok | {:error, term()})}
          | {:now_fun, (-> DateTime.t())}
          | {:memory_sample_fun, (-> memory_sample())}
          | {:memory_sample_interval_ms, pos_integer()}
          | {:environment_fun, (-> map())}
          | {:repository_fun, (-> map())}

  @doc "Returns the fixed source, selection, and output contract."
  @spec configuration() :: configuration()
  def configuration do
    %{
      schema_version: @schema_version,
      experiment_id: @experiment_id,
      source_url: @source_url,
      year: @year,
      quarter: @quarter,
      filters: %{
        "agglvl_code" => "70",
        "industry_code" => "10",
        "own_code" => "0",
        "size_code" => "0"
      },
      grouping_key: "first two characters of area_fips",
      input_columns: @input_columns,
      output_columns: @output_columns
    }
  end

  @doc "Transforms a QCEW CSV binary according to the comparison contract."
  @spec transform_csv(binary()) :: {:ok, transform_result()} | {:error, term()}
  def transform_csv(csv) when is_binary(csv) do
    transform(fn -> DataFrame.load_csv!(csv, csv_options()) end)
  end

  @doc "Transforms a QCEW CSV file according to the comparison contract."
  @spec transform_file(Path.t()) :: {:ok, transform_result()} | {:error, term()}
  def transform_file(path) when is_binary(path) do
    transform(fn -> DataFrame.from_csv!(path, csv_options()) end)
  end

  @doc "Downloads or reuses the fixed source, runs measurements, and emits ignored artifacts."
  @spec run([run_option()]) :: {:ok, execution()} | {:error, term()}
  def run(opts \\ []) do
    source_path = Keyword.get(opts, :source_path, @default_source_path)
    output_dir = Keyword.get(opts, :output_dir, @default_output_dir)
    iterations = Keyword.get(opts, :iterations, @default_iterations)
    now_fun = Keyword.get(opts, :now_fun, &default_now/0)

    with :ok <- validate_iterations(iterations),
         :ok <- validate_run_options(source_path, output_dir, opts),
         {:ok, run_started_at} <- utc_time(now_fun),
         opts = Keyword.put(opts, :run_started_at, run_started_at),
         {:ok, source} <- acquire_source(source_path, opts),
         {:ok, benchmark, result} <- benchmark(source_path, iterations, source, opts),
         {:ok, execution} <- emit_artifacts(output_dir, source, benchmark, result, opts) do
      {:ok, execution}
    end
  end

  defp transform(loader) do
    dataframe = loader.()
    source_row_count = DataFrame.n_rows(dataframe)

    normalized =
      DataFrame.mutate_with(dataframe, fn lazy ->
        [
          area_fips: lazy["area_fips"] |> Series.fill_missing("") |> Series.strip(),
          own_code: lazy["own_code"] |> Series.fill_missing("") |> Series.strip(),
          industry_code: lazy["industry_code"] |> Series.fill_missing("") |> Series.strip(),
          agglvl_code: lazy["agglvl_code"] |> Series.fill_missing("") |> Series.strip(),
          size_code: lazy["size_code"] |> Series.fill_missing("") |> Series.strip(),
          year: lazy["year"] |> Series.fill_missing("") |> Series.strip(),
          qtr: lazy["qtr"] |> Series.fill_missing("") |> Series.strip(),
          disclosure_code: lazy["disclosure_code"] |> Series.fill_missing("") |> Series.strip()
        ]
      end)

    selected_with_disclosure =
      DataFrame.filter(
        normalized,
        year == "2024" and qtr == "1" and industry_code == "10" and own_code == "0" and
          size_code == "0" and agglvl_code == "70"
      )

    undisclosed_row_count =
      selected_with_disclosure
      |> DataFrame.filter(disclosure_code != "")
      |> DataFrame.n_rows()

    selected = DataFrame.filter(selected_with_disclosure, disclosure_code == "")
    selected_row_count = DataFrame.n_rows(selected)

    with :ok <- ensure_disclosed(undisclosed_row_count),
         :ok <- ensure_selected_rows(selected_row_count),
         :ok <- ensure_area_fips(selected),
         :ok <- ensure_complete_measures(selected) do
      grouped = group_selected_rows(selected)
      csv = DataFrame.dump_csv!(grouped, quote_style: :necessary)
      rows = DataFrame.to_rows(grouped)

      {:ok,
       %{
         csv: csv,
         sha256: sha256(csv),
         source_row_count: source_row_count,
         selected_row_count: selected_row_count,
         output_row_count: length(rows),
         totals: result_totals(rows)
       }}
    end
  rescue
    exception in [ArgumentError, RuntimeError] ->
      {:error, {:invalid_qcew_csv, Exception.message(exception)}}
  end

  defp group_selected_rows(selected) do
    selected
    |> DataFrame.mutate_with(fn lazy ->
      [state_fips: Series.substring(lazy["area_fips"], 0, 2)]
    end)
    |> DataFrame.group_by("state_fips", stable: true)
    |> DataFrame.summarise_with(fn lazy ->
      [
        county_rows: Series.count(lazy["area_fips"]),
        qtrly_estabs: Series.sum(lazy["qtrly_estabs"]),
        month1_emplvl: Series.sum(lazy["month1_emplvl"]),
        month2_emplvl: Series.sum(lazy["month2_emplvl"]),
        month3_emplvl: Series.sum(lazy["month3_emplvl"]),
        total_qtrly_wages: Series.sum(lazy["total_qtrly_wages"])
      ]
    end)
    |> DataFrame.select(@output_columns)
    |> DataFrame.sort_by(asc: state_fips)
  end

  defp ensure_selected_rows(0), do: {:error, :no_selected_qcew_rows}
  defp ensure_selected_rows(_count), do: :ok

  defp ensure_disclosed(0), do: :ok
  defp ensure_disclosed(count), do: {:error, {:undisclosed_selected_rows, count}}

  defp ensure_area_fips(selected) do
    area_fips = selected["area_fips"] |> Series.to_list() |> Enum.sort()
    invalid = Enum.reject(area_fips, &Regex.match?(~r/^\d{5}$/, &1))

    duplicates =
      area_fips
      |> Enum.frequencies()
      |> Enum.filter(fn {_value, count} -> count > 1 end)
      |> Enum.map(fn {value, _count} -> value end)
      |> Enum.sort()

    cond do
      invalid != [] -> {:error, {:invalid_selected_area_fips, invalid}}
      duplicates != [] -> {:error, {:duplicate_selected_area_fips, duplicates}}
      true -> :ok
    end
  end

  defp ensure_complete_measures(selected) do
    nil_counts =
      selected
      |> DataFrame.select(@measure_columns)
      |> DataFrame.nil_count()
      |> DataFrame.to_rows()
      |> List.first()

    missing =
      nil_counts
      |> Enum.filter(fn {_column, count} -> count > 0 end)
      |> Map.new()

    if missing == %{}, do: :ok, else: {:error, {:missing_selected_values, missing}}
  end

  defp result_totals(rows) do
    Enum.reduce(rows, Map.new(total_columns(), &{&1, 0}), fn row, totals ->
      Map.new(totals, fn {column, total} -> {column, total + Map.fetch!(row, column)} end)
    end)
  end

  defp total_columns, do: @output_columns -- ["state_fips"]

  defp csv_options do
    [
      columns: @input_columns,
      dtypes:
        Enum.map(@id_columns, &{&1, :string}) ++
          Enum.map(@measure_columns, &{&1, {:s, 64}}),
      infer_schema_length: 1_000
    ]
  end

  defp acquire_source(source_path, opts) do
    refresh? = Keyword.get(opts, :refresh_source, false)
    metadata_path = source_metadata_path(source_path)

    cond do
      refresh? ->
        with :ok <- authorize_refresh(source_path, metadata_path) do
          download_source(source_path, metadata_path, opts)
        end

      File.regular?(source_path) and File.regular?(metadata_path) ->
        reuse_source(source_path, metadata_path)

      File.exists?(source_path) or File.exists?(metadata_path) ->
        {:error, {:incomplete_source_cache, source_path, metadata_path}}

      not File.exists?(source_path) and not File.exists?(metadata_path) ->
        download_source(source_path, metadata_path, opts)
    end
  end

  defp authorize_refresh(source_path, metadata_path) do
    cond do
      not File.exists?(source_path) and not File.exists?(metadata_path) ->
        :ok

      File.regular?(metadata_path) ->
        with {:ok, encoded} <- File.read(metadata_path),
             {:ok, metadata} <- Jason.decode(encoded),
             true <- metadata["schema_version"] == @source_metadata_version,
             true <- metadata["source_url"] == @source_url do
          :ok
        else
          _other -> {:error, {:refuse_unmanaged_source_overwrite, source_path}}
        end

      true ->
        {:error, {:refuse_unmanaged_source_overwrite, source_path}}
    end
  end

  defp reuse_source(source_path, metadata_path) do
    with {:ok, encoded} <- File.read(metadata_path),
         {:ok, metadata} <- Jason.decode(encoded),
         :ok <- validate_source_metadata(metadata, source_path) do
      {:ok, Map.put(metadata, "cache_state", "reused_verified_local_file")}
    else
      {:error, %Jason.DecodeError{} = error} ->
        {:error, {:invalid_source_metadata, Exception.message(error)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_source_metadata(metadata, source_path) do
    actual_sha256 = file_sha256(source_path)
    actual_byte_count = File.stat!(source_path).size

    cond do
      metadata["schema_version"] != @source_metadata_version ->
        {:error, {:source_metadata_version_mismatch, metadata["schema_version"]}}

      metadata["source_url"] != @source_url ->
        {:error, {:source_url_mismatch, metadata["source_url"]}}

      metadata["sha256"] != actual_sha256 ->
        {:error, {:source_sha256_mismatch, metadata["sha256"], actual_sha256}}

      metadata["byte_count"] != actual_byte_count ->
        {:error, {:source_byte_count_mismatch, metadata["byte_count"], actual_byte_count}}

      not valid_utc_timestamp?(metadata["retrieved_at"]) ->
        {:error, {:invalid_source_retrieval_time, metadata["retrieved_at"]}}

      true ->
        :ok
    end
  end

  defp download_source(source_path, metadata_path, opts) do
    download_fun = Keyword.get(opts, :download_fun, &download/2)
    retrieved_at = Keyword.fetch!(opts, :run_started_at)
    temporary_path = temporary_path(source_path)

    File.mkdir_p!(Path.dirname(source_path))

    try do
      case download_fun.(@source_url, temporary_path) do
        :ok ->
          metadata = %{
            "schema_version" => @source_metadata_version,
            "source_url" => @source_url,
            "retrieved_at" => DateTime.to_iso8601(retrieved_at),
            "sha256" => file_sha256(temporary_path),
            "byte_count" => File.stat!(temporary_path).size
          }

          with :ok <- File.rename(temporary_path, source_path),
               :ok <- atomic_write(metadata_path, Jason.encode!(metadata, pretty: true) <> "\n") do
            {:ok, Map.put(metadata, "cache_state", "downloaded_this_run")}
          end

        {:error, reason} ->
          {:error, {:source_download_failed, reason}}
      end
    rescue
      exception ->
        {:error, {:source_download_failed, Exception.message(exception)}}
    after
      File.rm(temporary_path)
    end
  end

  defp download(url, path) do
    case Req.get(url, into: File.stream!(path), receive_timeout: 60_000) do
      {:ok, %Req.Response{status: 200}} -> :ok
      {:ok, %Req.Response{status: status}} -> {:error, {:http_status, status}}
      {:error, exception} -> {:error, {:request_error, Exception.message(exception)}}
    end
  end

  defp benchmark(source_path, iterations, source, opts) do
    memory_sample_fun = Keyword.get(opts, :memory_sample_fun, &memory_sample/0)
    interval_ms = Keyword.get(opts, :memory_sample_interval_ms, 5)

    1..iterations
    |> Enum.reduce_while({:ok, [], nil}, fn index, {:ok, measurements, expected_result} ->
      :erlang.garbage_collect()

      case measure(
             fn -> transform_file(source_path) end,
             memory_sample_fun,
             interval_ms
           ) do
        {:ok, {:ok, result}, timing} ->
          with :ok <- ensure_repeatable(expected_result, result) do
            measurement =
              Map.merge(timing, %{
                "iteration" => index,
                "runtime_state" => if(index == 1, do: "cold_runtime", else: "warm_runtime"),
                "source_file_state" => source["cache_state"]
              })

            {:cont, {:ok, [measurement | measurements], expected_result || result}}
          else
            {:error, reason} -> {:halt, {:error, reason}}
          end

        {:ok, {:error, reason}, _timing} ->
          {:halt, {:error, reason}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, measurements, result} ->
        benchmark = %{
          "scope" =>
            "Explorer CSV parse, contract validation, filter, group, sort, and in-memory CSV serialization",
          "excludes" => [
            "network download",
            "source-cache validation",
            "result and manifest file writes",
            "environment and repository metadata collection"
          ],
          "iterations" => iterations,
          "clock" => "System.monotonic_time(:nanosecond)",
          "memory_method" =>
            "sampled process RSS and :erlang.memory(:total); instrumentation overhead is included",
          "memory_sample_interval_milliseconds" => interval_ms,
          "pre_iteration_cleanup" => "full BEAM garbage collection before each timed transform",
          "filesystem_cache_state" => "uncontrolled",
          "runtime_state_definitions" => %{
            "cold_runtime" => "first timed transform in the current BEAM instance",
            "warm_runtime" => "later timed transform in the same BEAM instance"
          },
          "measurements" => Enum.reverse(measurements)
        }

        {:ok, benchmark, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp measure(fun, memory_sample_fun, interval_ms) do
    parent = self()
    reference = make_ref()

    sampler =
      spawn(fn ->
        initial = memory_sample_fun.()
        send(parent, {reference, :ready, initial})
        memory_sample_loop(parent, reference, memory_sample_fun, interval_ms, initial)
      end)

    receive do
      {^reference, :ready, initial} ->
        try do
          started_at = System.monotonic_time(:nanosecond)
          result = fun.()
          elapsed = System.monotonic_time(:nanosecond) - started_at
          final = memory_sample_fun.()
          send(sampler, {reference, :stop, final})

          receive do
            {^reference, :stopped, peak} ->
              {:ok, result,
               %{
                 "elapsed_nanoseconds" => elapsed,
                 "memory_before" => initial,
                 "peak_memory" => peak,
                 "peak_memory_delta" => memory_delta(peak, initial)
               }}
          after
            5_000 -> {:error, :memory_sampler_stop_timeout}
          end
        rescue
          exception ->
            send(sampler, {reference, :stop, memory_sample_fun.()})
            {:error, {:benchmark_failed, Exception.message(exception)}}
        end
    after
      5_000 ->
        Process.exit(sampler, :kill)
        {:error, :memory_sampler_start_timeout}
    end
  end

  defp memory_sample_loop(parent, reference, sample_fun, interval_ms, peak) do
    receive do
      {^reference, :stop, final} ->
        send(parent, {reference, :stopped, max_memory(peak, final)})
    after
      interval_ms ->
        memory_sample_loop(
          parent,
          reference,
          sample_fun,
          interval_ms,
          max_memory(peak, sample_fun.())
        )
    end
  end

  defp max_memory(left, right) do
    Map.new(Map.keys(left) ++ Map.keys(right), fn key ->
      {key, max_optional(left[key], right[key])}
    end)
  end

  defp max_optional(nil, value), do: value
  defp max_optional(value, nil), do: value
  defp max_optional(left, right), do: max(left, right)

  defp memory_delta(peak, initial) do
    Map.new(peak, fn {key, peak_value} ->
      initial_value = initial[key]

      delta =
        if is_integer(peak_value) and is_integer(initial_value),
          do: max(peak_value - initial_value, 0),
          else: nil

      {key, delta}
    end)
  end

  defp ensure_repeatable(nil, _result), do: :ok

  defp ensure_repeatable(expected, actual) do
    if expected.sha256 == actual.sha256,
      do: :ok,
      else: {:error, {:non_repeatable_result, expected.sha256, actual.sha256}}
  end

  defp emit_artifacts(output_dir, source, benchmark, result, opts) do
    environment_fun = Keyword.get(opts, :environment_fun, &environment_metadata/0)
    repository_fun = Keyword.get(opts, :repository_fun, &repository_metadata/0)
    generated_at = Keyword.fetch!(opts, :run_started_at)
    result_path = Path.join(output_dir, @result_filename)
    manifest_path = Path.join(output_dir, @manifest_filename)

    File.mkdir_p!(output_dir)

    with :ok <- atomic_write(result_path, result.csv) do
      environment =
        environment_fun.()
        |> Map.put("host_hardware", host_hardware_metadata(opts))

      manifest =
        build_manifest(
          source,
          benchmark,
          result,
          generated_at,
          environment,
          repository_fun.()
        )

      with :ok <- atomic_write(manifest_path, Jason.encode!(manifest, pretty: true) <> "\n") do
        {:ok,
         %{
           result_path: result_path,
           manifest_path: manifest_path,
           manifest: manifest
         }}
      end
    end
  end

  defp build_manifest(source, benchmark, result, generated_at, environment, repository) do
    source_manifest =
      source
      |> Map.put("publisher", "U.S. Bureau of Labor Statistics")
      |> Map.put("dataset", "Quarterly Census of Employment and Wages")
      |> Map.put("media_type", "text/csv")
      |> Map.put("retrieval_date", String.slice(source["retrieved_at"], 0, 10))
      |> Map.put("copyright_status", "BLS-published material is public domain")
      |> Map.put("copyright_url", "https://www.bls.gov/opub/copyright-information.htm")
      |> Map.put("terms_url", "https://www.bls.gov/developers/termsOfService.htm")
      |> Map.put(
        "permitted_use",
        "BLS public-domain material may be used without specific permission; cite BLS and preserve the retrieval date and BLS disclaimer"
      )
      |> Map.put(
        "bls_disclaimer",
        "BLS.gov cannot vouch for the data or analyses derived from these data after the data have been retrieved from BLS.gov."
      )

    %{
      "schema_version" => @schema_version,
      "experiment_id" => @experiment_id,
      "generated_at" => generated_at |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      "source" => source_manifest,
      "contract" => %{
        "year" => @year,
        "quarter" => @quarter,
        "slice" => %{"kind" => "industry", "industry_code" => "10"},
        "filters" => configuration().filters,
        "disclosure_rule" => "fail if any selected row has a nonblank disclosure_code",
        "area_fips_rule" => "require one unique five-digit county area_fips per selected row",
        "grouping_key" => configuration().grouping_key,
        "aggregations" => %{
          "county_rows" => "count selected rows",
          "month1_emplvl" => "integer sum",
          "month2_emplvl" => "integer sum",
          "month3_emplvl" => "integer sum",
          "qtrly_estabs" => "integer sum",
          "total_qtrly_wages" => "integer sum"
        },
        "output_columns" => @output_columns,
        "ordering" => ["state_fips ascending"],
        "csv" => %{
          "delimiter" => ",",
          "encoding" => "UTF-8",
          "header" => true,
          "line_ending" => "LF",
          "final_newline" => true
        }
      },
      "result" => %{
        "path" => @result_filename,
        "sha256" => result.sha256,
        "byte_count" => byte_size(result.csv),
        "source_row_count" => result.source_row_count,
        "selected_row_count" => result.selected_row_count,
        "row_count" => result.output_row_count,
        "totals" => result.totals
      },
      "benchmark" => benchmark,
      "environment" => environment,
      "repository" => repository,
      "claims" => %{
        "causal" => false,
        "predictive" => false,
        "recession" => false,
        "financial" => false,
        "interpretation" =>
          "The result is a deterministic engineering comparison artifact, not an economic conclusion."
      }
    }
  end

  defp environment_metadata do
    %{
      "hardware" => %{
        "architecture" => to_string(:erlang.system_info(:system_architecture)),
        "cpu_model" => cpu_model(),
        "logical_processors" => :erlang.system_info(:logical_processors_available),
        "memory_total_bytes" => memory_total_bytes(),
        "container_memory_limit_bytes" => container_memory_limit_bytes()
      },
      "os" => %{
        "family" => :os.type() |> elem(0) |> to_string(),
        "name" => :os.type() |> elem(1) |> to_string(),
        "version" => :os.version() |> Tuple.to_list() |> Enum.join(".")
      },
      "runtime" => %{
        "elixir" => System.version(),
        "otp" => to_string(:erlang.system_info(:otp_release)),
        "erts" => to_string(:erlang.system_info(:version)),
        "explorer" => application_version(:explorer),
        "jason" => application_version(:jason)
      }
    }
  end

  defp host_hardware_metadata(opts) do
    values = %{
      "label" => Keyword.get(opts, :host_hardware_label),
      "cpu_model" => Keyword.get(opts, :host_cpu_model),
      "logical_processors" => Keyword.get(opts, :host_logical_processors),
      "memory_total_bytes" => Keyword.get(opts, :host_memory_bytes)
    }

    source =
      if Enum.any?(values, fn {_key, value} -> not is_nil(value) end),
        do: "operator_provided",
        else: "not_provided"

    Map.put(values, "metadata_source", source)
  end

  defp repository_metadata do
    %{
      "commit" => git_output(["rev-parse", "HEAD"]),
      "dirty" => git_output(["status", "--porcelain"]) not in [nil, ""]
    }
  end

  defp git_output(arguments) do
    repository_path = File.cwd!()

    case System.cmd("git", ["-c", "safe.directory=#{repository_path}" | arguments],
           stderr_to_stdout: true
         ) do
      {output, 0} -> String.trim(output)
      _other -> nil
    end
  end

  defp memory_sample do
    %{
      "beam_total_bytes" => :erlang.memory(:total),
      "rss_bytes" => resident_set_size_bytes()
    }
  end

  defp resident_set_size_bytes do
    linux_status_path = "/proc/#{System.pid()}/status"

    cond do
      File.regular?(linux_status_path) ->
        with {:ok, status} <- File.read(linux_status_path),
             [_, kilobytes] <- Regex.run(~r/^VmRSS:\s+(\d+)\s+kB$/m, status) do
          String.to_integer(kilobytes) * 1_024
        else
          _ -> nil
        end

      match?({:unix, :darwin}, :os.type()) ->
        case System.cmd("ps", ["-o", "rss=", "-p", System.pid()], stderr_to_stdout: true) do
          {output, 0} -> parse_kilobytes(output)
          _other -> nil
        end

      true ->
        nil
    end
  end

  defp cpu_model do
    cond do
      File.regular?("/proc/cpuinfo") ->
        with {:ok, cpuinfo} <- File.read("/proc/cpuinfo"),
             [_, model] <- Regex.run(~r/^model name\s*:\s*(.+)$/m, cpuinfo) do
          String.trim(model)
        else
          _ -> "unavailable"
        end

      match?({:unix, :darwin}, :os.type()) ->
        sysctl_value("machdep.cpu.brand_string") || sysctl_value("hw.model") || "unavailable"

      true ->
        "unavailable"
    end
  end

  defp memory_total_bytes do
    cond do
      File.regular?("/proc/meminfo") ->
        with {:ok, meminfo} <- File.read("/proc/meminfo"),
             [_, kilobytes] <- Regex.run(~r/^MemTotal:\s+(\d+)\s+kB$/m, meminfo) do
          String.to_integer(kilobytes) * 1_024
        else
          _ -> nil
        end

      match?({:unix, :darwin}, :os.type()) ->
        case sysctl_value("hw.memsize") do
          nil -> nil
          bytes -> String.to_integer(bytes)
        end

      true ->
        nil
    end
  end

  defp container_memory_limit_bytes do
    ["/sys/fs/cgroup/memory.max", "/sys/fs/cgroup/memory/memory.limit_in_bytes"]
    |> Enum.find_value(fn path ->
      if File.regular?(path) do
        case path |> File.read!() |> String.trim() do
          "max" -> nil
          value -> String.to_integer(value)
        end
      end
    end)
  rescue
    _exception -> nil
  end

  defp sysctl_value(name) do
    case System.cmd("sysctl", ["-n", name], stderr_to_stdout: true) do
      {output, 0} -> String.trim(output)
      _other -> nil
    end
  end

  defp parse_kilobytes(value) do
    case Integer.parse(String.trim(value)) do
      {kilobytes, ""} -> kilobytes * 1_024
      _other -> nil
    end
  end

  defp application_version(application) do
    case Application.spec(application, :vsn) do
      nil -> "unavailable"
      version -> to_string(version)
    end
  end

  defp valid_utc_timestamp?(value) when is_binary(value) do
    match?({:ok, %DateTime{}, 0}, DateTime.from_iso8601(value))
  end

  defp valid_utc_timestamp?(_value), do: false

  defp utc_time(now_fun) do
    case now_fun.() do
      %DateTime{utc_offset: utc_offset, std_offset: std_offset} = value
      when utc_offset + std_offset == 0 ->
        {:ok, DateTime.truncate(value, :second)}

      value ->
        {:error, {:invalid_retrieval_time, value}}
    end
  rescue
    exception -> {:error, {:invalid_retrieval_time, Exception.message(exception)}}
  end

  defp validate_run_options(source_path, output_dir, opts) do
    with :ok <- validate_path(:source_path, source_path),
         :ok <- validate_path(:output_dir, output_dir),
         :ok <-
           validate_optional_positive_integer(
             opts,
             :host_logical_processors,
             :invalid_host_logical_processors
           ),
         :ok <-
           validate_optional_positive_integer(
             opts,
             :host_memory_bytes,
             :invalid_host_memory_bytes
           ),
         :ok <-
           validate_optional_positive_integer(
             opts,
             :memory_sample_interval_ms,
             :invalid_memory_sample_interval
           ) do
      :ok
    end
  end

  defp validate_path(_name, path) when is_binary(path) and byte_size(path) > 0, do: :ok
  defp validate_path(name, path), do: {:error, {:invalid_path, name, path}}

  defp validate_optional_positive_integer(opts, key, error_tag) do
    case Keyword.fetch(opts, key) do
      :error -> :ok
      {:ok, value} when is_integer(value) and value > 0 -> :ok
      {:ok, value} -> {:error, {error_tag, value}}
    end
  end

  defp validate_iterations(iterations) when is_integer(iterations) and iterations >= 2, do: :ok
  defp validate_iterations(iterations), do: {:error, {:invalid_iterations, iterations}}

  defp source_metadata_path(source_path), do: source_path <> ".source-metadata.v1.json"

  defp temporary_path(path) do
    path <> ".tmp-#{System.unique_integer([:positive, :monotonic])}"
  end

  defp atomic_write(path, contents) do
    File.mkdir_p!(Path.dirname(path))
    temporary_path = temporary_path(path)

    result =
      with :ok <- File.write(temporary_path, contents, [:binary]),
           :ok <- File.rename(temporary_path, path) do
        :ok
      end

    if result != :ok, do: File.rm(temporary_path)
    result
  end

  defp file_sha256(path) do
    path
    |> File.stream!(1_048_576, [])
    |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
  end

  defp sha256(value) do
    :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
  end

  defp default_now, do: DateTime.utc_now()
end
