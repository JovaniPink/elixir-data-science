defmodule ElixirDataScience.RegionalSourceBuilder do
  @moduledoc """
  Builds the ignored normalized source bundle from receipt-pinned local bytes.

  Refresh is explicit and accepts publisher bytes only when their SHA-256 and
  byte count already match the candidate receipt. Existing unmanaged files are
  never overwritten.
  """

  alias ElixirDataScience.RegionalExpertEnsemble, as: Regional

  @normalized_columns %{
    "qcew" => [
      "state_fips",
      "observation_quarter",
      "release_date",
      "vintage",
      "status",
      "employment",
      "establishments",
      "total_wages"
    ],
    "bea" => [
      "state_fips",
      "observation_quarter",
      "release_date",
      "vintage",
      "real_gdp",
      "personal_income"
    ],
    "fhfa" => [
      "state_fips",
      "observation_quarter",
      "release_date",
      "report_url",
      "hpi_qoq",
      "hpi_yoy"
    ]
  }

  @spec build(Path.t(), Path.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def build(candidate_path, output_dir, opts \\ []) do
    refresh? = Keyword.get(opts, :refresh_source, false)
    download_fun = Keyword.get(opts, :download_fun, &download/1)

    with {:ok, bytes} <- File.read(candidate_path),
         {:ok, bundle} <- Jason.decode(bytes),
         :ok <- maybe_refresh(bundle["sources"], refresh?, download_fun),
         :ok <- Regional.validate_source_bundle(bundle),
         :ok <- File.mkdir_p(output_dir),
         :ok <- emit_bundle(bundle, output_dir),
         :ok <- emit_normalized(bundle["observations"], output_dir) do
      {:ok,
       %{
         "output_dir" => output_dir,
         "contract_sha256" => Regional.contract_sha256(),
         "source_count" => length(bundle["sources"]),
         "refresh_source" => refresh?
       }}
    end
  end

  defp maybe_refresh(_receipts, false, _download_fun), do: :ok

  defp maybe_refresh(receipts, true, download_fun) when is_list(receipts) do
    with {:ok, staged} <- stage_downloads(receipts, download_fun),
         :ok <- authorize_targets(staged),
         :ok <- persist_downloads(staged) do
      :ok
    end
  end

  defp maybe_refresh(_receipts, true, _download_fun), do: {:error, :invalid_source_receipts}

  defp stage_downloads(receipts, download_fun) do
    Enum.reduce_while(receipts, {:ok, []}, fn receipt, {:ok, staged} ->
      with {:ok, downloaded} <- download_fun.(receipt["publisher_url"]),
           true <- byte_size(downloaded) == receipt["byte_count"],
           true <- sha256(downloaded) == receipt["sha256"] do
        {:cont, {:ok, [{receipt, downloaded} | staged]}}
      else
        false ->
          {:halt, {:error, {:refreshed_source_receipt_mismatch, receipt["source_id"]}}}

        {:error, reason} ->
          {:halt, {:error, {:source_refresh_failed, receipt["source_id"], reason}}}
      end
    end)
    |> case do
      {:ok, staged} -> {:ok, Enum.reverse(staged)}
      error -> error
    end
  end

  defp authorize_targets(staged) do
    Enum.reduce_while(staged, :ok, fn {receipt, _bytes}, :ok ->
      path = receipt["cache_path"]
      sidecar = path <> ".regional-source-receipt.json"

      cond do
        not File.exists?(path) ->
          {:cont, :ok}

        not File.exists?(sidecar) ->
          {:halt, {:error, {:refuse_unmanaged_source_overwrite, path}}}

        true ->
          case sidecar |> File.read!() |> Jason.decode() do
            {:ok, %{"schema_version" => "regional-source-cache.v1", "source_id" => source_id}} ->
              if source_id == receipt["source_id"] do
                {:cont, :ok}
              else
                {:halt, {:error, {:refuse_unmanaged_source_overwrite, path}}}
              end

            _other ->
              {:halt, {:error, {:refuse_unmanaged_source_overwrite, path}}}
          end
      end
    end)
  end

  defp persist_downloads(staged) do
    Enum.each(staged, fn {receipt, bytes} ->
      path = receipt["cache_path"]
      File.mkdir_p!(Path.dirname(path))
      temporary = path <> ".regional-download"
      File.write!(temporary, bytes)
      File.rename!(temporary, path)

      sidecar = %{
        "schema_version" => "regional-source-cache.v1",
        "source_id" => receipt["source_id"],
        "publisher_url" => receipt["publisher_url"],
        "sha256" => receipt["sha256"],
        "byte_count" => receipt["byte_count"]
      }

      File.write!(path <> ".regional-source-receipt.json", Jason.encode!(sidecar) <> "\n")
    end)

    :ok
  end

  defp emit_bundle(bundle, output_dir) do
    File.write(
      Path.join(output_dir, "regional-source-bundle.v1.json"),
      Jason.encode!(bundle) <> "\n"
    )
  end

  defp emit_normalized(observations, output_dir) do
    Enum.each(@normalized_columns, fn {source, columns} ->
      csv = Regional.canonical_csv(observations[source], columns)
      File.write!(Path.join(output_dir, "#{source}-vintages.v1.csv"), csv)
    end)

    :ok
  end

  defp download(url) do
    case Req.get(url) do
      {:ok, %{status: 200, body: body}} when is_binary(body) -> {:ok, body}
      {:ok, response} -> {:error, {:unexpected_status, response.status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp sha256(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
end
