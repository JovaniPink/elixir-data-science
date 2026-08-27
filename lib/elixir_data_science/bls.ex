defmodule ElixirDataScience.BLS do
  @moduledoc """
  Minimal client and parser for the BLS Public Data API.

  Anonymous requests are divided into inclusive windows of at most ten years,
  matching the published unregistered-user limit. Raw responses are not
  persisted by this module.
  """

  @endpoint "https://api.bls.gov/publicAPI/v2/timeseries/data/"
  @series_ids ["CUUR0000SA0", "LNS14000000"]
  @max_unregistered_years 10

  @type series_id :: String.t()

  @type point :: %{
          date: Date.t(),
          value: float(),
          preliminary?: boolean()
        }

  @type unavailable_point :: %{
          date: Date.t(),
          value: String.t(),
          footnotes: [String.t()]
        }

  @type dataset :: %{
          source_url: String.t(),
          retrieved_at: DateTime.t(),
          start_year: pos_integer(),
          end_year: pos_integer(),
          request_mode: :anonymous | :registered,
          request_windows: [{pos_integer(), pos_integer()}],
          series: %{required(series_id()) => [point()]},
          unavailable: %{required(series_id()) => [unavailable_point()]},
          messages: [String.t()]
        }

  @type request_payload :: %{
          required(String.t()) => String.t() | [series_id()]
        }

  @type request_fun :: (request_payload() -> {:ok, map()} | {:error, term()})

  @type fetch_option ::
          {:request_fun, request_fun()}
          | {:registration_key, String.t()}

  @type parsed_response :: %{
          series: %{required(series_id()) => [point()]},
          unavailable: %{required(series_id()) => [unavailable_point()]}
        }

  @doc "Returns the two BLS series IDs used by the experiment."
  @spec series_ids() :: [series_id()]
  def series_ids, do: @series_ids

  @doc "Returns the BLS API endpoint used for retrieval."
  @spec endpoint() :: String.t()
  def endpoint, do: @endpoint

  @doc """
  Retrieves CPI-U and unemployment data for the inclusive year range.

  Pass `:request_fun` in tests to replace the network request. A BLS API key
  may be supplied with `:registration_key`, but the default path is anonymous
  and does not require credentials.
  """
  @spec fetch(pos_integer(), pos_integer(), [fetch_option()]) ::
          {:ok, dataset()} | {:error, term()}
  def fetch(start_year, end_year, opts \\ []) do
    with :ok <- validate_years(start_year, end_year) do
      request_fun = Keyword.get(opts, :request_fun, &request/1)
      registration_key = Keyword.get(opts, :registration_key)
      request_mode = request_mode(registration_key)
      windows = year_windows(start_year, end_year)

      windows
      |> Enum.reduce_while({:ok, %{}, %{}, []}, fn {window_start, window_end},
                                                   {:ok, series_acc, unavailable_acc,
                                                    messages_acc} ->
        payload = payload(window_start, window_end, registration_key)

        with {:ok, body} <- request_fun.(payload),
             {:ok, parsed, messages} <- parse_response(body) do
          {:cont,
           {:ok, merge_series(series_acc, parsed.series),
            merge_unavailable(unavailable_acc, parsed.unavailable), messages_acc ++ messages}}
        else
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
      |> case do
        {:ok, series, unavailable, messages} ->
          {:ok,
           %{
             source_url: @endpoint,
             retrieved_at: DateTime.utc_now() |> DateTime.truncate(:second),
             start_year: start_year,
             end_year: end_year,
             request_mode: request_mode,
             request_windows: windows,
             series: series,
             unavailable: unavailable,
             messages: Enum.uniq(messages)
           }}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc "Builds inclusive windows that comply with the anonymous 10-year limit."
  @spec year_windows(pos_integer(), pos_integer()) ::
          [{pos_integer(), pos_integer()}]
  def year_windows(start_year, end_year) when start_year <= end_year do
    Stream.unfold(start_year, fn
      year when year > end_year ->
        nil

      year ->
        window_end = min(year + @max_unregistered_years - 1, end_year)
        {{year, window_end}, window_end + 1}
    end)
    |> Enum.to_list()
  end

  @doc "Parses one successful BLS response into normalized monthly series."
  @spec parse_response(map()) ::
          {:ok, parsed_response(), [String.t()]}
          | {:error, term()}
  def parse_response(%{"status" => "REQUEST_SUCCEEDED"} = body) do
    with {:ok, series_entries} <- result_series(body),
         {:ok, parsed} <- parse_series_entries(series_entries) do
      {:ok, parsed, normalize_messages(Map.get(body, "message", []))}
    end
  end

  def parse_response(%{"status" => status} = body) do
    {:error, {:bls_request_failed, status, normalize_messages(Map.get(body, "message", []))}}
  end

  def parse_response(body), do: {:error, {:unexpected_bls_response, body}}

  defp request(payload) do
    case Req.post(@endpoint, json: payload, receive_timeout: 30_000) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:http_status, status, body}}

      {:error, exception} ->
        {:error, {:request_error, exception}}
    end
  end

  defp payload(start_year, end_year, registration_key) do
    %{
      "seriesid" => @series_ids,
      "startyear" => Integer.to_string(start_year),
      "endyear" => Integer.to_string(end_year)
    }
    |> maybe_put_registration_key(registration_key)
  end

  defp maybe_put_registration_key(payload, key) when is_binary(key) and key != "",
    do: Map.put(payload, "registrationkey", key)

  defp maybe_put_registration_key(payload, _key), do: payload

  defp request_mode(key) when is_binary(key) and key != "", do: :registered
  defp request_mode(_key), do: :anonymous

  defp result_series(%{"Results" => %{"series" => series}}) when is_list(series),
    do: {:ok, series}

  defp result_series(%{"Results" => results}) when is_list(results) do
    series = Enum.flat_map(results, &Map.get(&1, "series", []))
    {:ok, series}
  end

  defp result_series(_body), do: {:error, :missing_bls_series}

  defp parse_series_entries(entries) do
    entries
    |> Enum.reduce_while({:ok, %{series: %{}, unavailable: %{}}}, fn entry, {:ok, acc} ->
      case parse_series(entry) do
        {:ok, id, points, unavailable} ->
          {:cont,
           {:ok,
            %{
              series: Map.put(acc.series, id, points),
              unavailable: Map.put(acc.unavailable, id, unavailable)
            }}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp parse_series(%{"seriesID" => id, "data" => data})
       when is_binary(id) and is_list(data) do
    {points, unavailable} =
      Enum.reduce(data, {[], []}, fn entry, {points, unavailable} ->
        case parse_monthly_entry(entry) do
          {:ok, point} -> {[point | points], unavailable}
          {:unavailable, point} -> {points, [point | unavailable]}
          :skip -> {points, unavailable}
        end
      end)

    {:ok, id, Enum.sort_by(points, & &1.date, Date), Enum.sort_by(unavailable, & &1.date, Date)}
  end

  defp parse_series(entry), do: {:error, {:invalid_bls_series, entry}}

  defp parse_monthly_entry(
         %{"year" => year, "period" => <<"M", month_text::binary-size(2)>>, "value" => value} =
           entry
       ) do
    with {year_number, ""} <- Integer.parse(year),
         {month_number, ""} <- Integer.parse(month_text),
         true <- month_number in 1..12,
         {:ok, date} <- Date.new(year_number, month_number, 1) do
      case value |> String.replace(",", "") |> Float.parse() do
        {number, ""} ->
          {:ok,
           %{
             date: date,
             value: number,
             preliminary?: preliminary?(Map.get(entry, "footnotes", []))
           }}

        :error ->
          {:unavailable,
           %{
             date: date,
             value: value,
             footnotes: footnote_texts(Map.get(entry, "footnotes", []))
           }}
      end
    else
      _ -> :skip
    end
  end

  defp parse_monthly_entry(_entry), do: :skip

  defp preliminary?(footnotes) when is_list(footnotes) do
    Enum.any?(footnotes, fn
      %{"code" => "P"} -> true
      %{"text" => text} when is_binary(text) -> String.contains?(text, "Preliminary")
      _ -> false
    end)
  end

  defp preliminary?(_footnotes), do: false

  defp footnote_texts(footnotes) when is_list(footnotes) do
    footnotes
    |> Enum.flat_map(fn
      %{"text" => text} when is_binary(text) and text != "" -> [text]
      _ -> []
    end)
    |> Enum.uniq()
  end

  defp footnote_texts(_footnotes), do: []

  defp merge_series(left, right) do
    Map.merge(left, right, fn _series_id, left_points, right_points ->
      (left_points ++ right_points)
      |> Map.new(&{&1.date, &1})
      |> Map.values()
      |> Enum.sort_by(& &1.date, Date)
    end)
  end

  defp merge_unavailable(left, right) do
    Map.merge(left, right, fn _series_id, left_points, right_points ->
      (left_points ++ right_points)
      |> Map.new(&{&1.date, &1})
      |> Map.values()
      |> Enum.sort_by(& &1.date, Date)
    end)
  end

  defp normalize_messages(messages) when is_list(messages) do
    messages
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_messages(_messages), do: []

  defp validate_years(start_year, end_year)
       when is_integer(start_year) and is_integer(end_year) and start_year > 0 and
              start_year <= end_year,
       do: :ok

  defp validate_years(start_year, end_year),
    do: {:error, {:invalid_year_range, start_year, end_year}}
end
