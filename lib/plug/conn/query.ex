defmodule Plug.Conn.Query do
  @moduledoc """
  Conveniences for decoding and encoding url encoded queries.

  Plug allows a developer to build query strings
  that map to Elixir structures in order to make
  manipulation of such structures easier on the server
  side. Here are some examples:

      iex> decode("foo=bar")["foo"]
      "bar"

  If a value is given more than once, the last value takes precedence:

      iex> decode("foo=bar&foo=baz")["foo"]
      "baz"

  Nested structures can be created via `[key]`:

      iex> decode("foo[bar]=baz")["foo"]["bar"]
      "baz"

  Lists are created with `[]`:

      iex> decode("foo[]=bar&foo[]=baz")["foo"]
      ["bar", "baz"]

  Dicts can be encoded:

      iex> encode(%{foo: "bar", baz: "bat"})
      "baz=bat&foo=bar"

  Encoding keyword lists preserves the order of the fields:

      iex> encode([foo: "bar", baz: "bat"])
      "foo=bar&baz=bat"

  When encoding keyword lists with duplicate keys, the key that comes first
  takes precedence:

      iex> encode([foo: "bar", foo: "bat"])
      "foo=bar"

  Encoding named lists:

      iex> encode(%{foo: ["bar", "baz"]})
      "foo[]=bar&foo[]=baz"

  Encoding nested structures:

      iex> encode(%{foo: %{bar: "baz"}})
      "foo[bar]=baz"

  """

  @doc """
  Decodes the given binary.
  """
  def decode(query, initial \\ %{})

  def decode("", initial) do
    initial
  end

  def decode(query, initial) do
    parts = :binary.split(query, "&", [:global])
    Enum.reduce(Enum.reverse(parts), initial, &decode_string_pair(&1, &2))
  end

  defp decode_string_pair(string, acc) do
    current =
      case :binary.split(string, "=") do
        [key, value] ->
          {URI.decode_www_form(key), URI.decode_www_form(value)}
        [key] ->
          {URI.decode_www_form(key), nil}
      end
    decode_pair(current, acc)
  end

  @doc """
  Decodes the given tuple and store it in the accumulator.
  It parses the key and stores the value into the current
  accumulator.

  Parameters lists are added to the accumulator in reverse
  order, so be sure to pass the parameters in reverse order.
  """
  def decode_pair({key, value}, acc) do
    parts =
      if key != "" and :binary.last(key) == ?] do
        # Remove trailing ]
        subkey = :binary.part(key, 0, byte_size(key) - 1)

        # Split the first [ then split remaining ][.
        #
        #     users[address][street #=> [ "users", "address][street" ]
        #
        case :binary.split(subkey, "[") do
          [key, subpart] ->
            [key|:binary.split(subpart, "][", [:global])]
          _ ->
            [key]
        end
      else
        [key]
      end

    assign_parts parts, value, acc
  end

  # We always assign the value in the last segment.
  # `age=17` would match here.
  defp assign_parts([key], value, acc) do
    Map.put_new(acc, key, value)
  end

  # The current segment is a list. We simply prepend
  # the item to the list or create a new one if it does
  # not yet. This assumes that items are iterated in
  # reverse order.
  defp assign_parts([key,""|t], value, acc) do
    case Map.fetch(acc, key) do
      {:ok, current} when is_list(current) ->
        Map.put(acc, key, assign_list(t, current, value))
      :error ->
        Map.put(acc, key, assign_list(t, [], value))
      _ ->
        acc
    end
  end

  # The current segment is a parent segment of a
  # map. We need to create a map and then
  # continue looping.
  defp assign_parts([key|t], value, acc) do
    case Map.fetch(acc, key) do
      {:ok, %{} = current} ->
        Map.put(acc, key, assign_parts(t, value, current))
      :error ->
        Map.put(acc, key, assign_parts(t, value, %{}))
      _ ->
        acc
    end
  end

  defp assign_list(t, current, value) do
    if value = assign_list(t, value), do: [value|current], else: current
  end

  defp assign_list([], value), do: value
  defp assign_list(t, value),  do: assign_parts(t, value, %{})

  @doc """
  Encodes the given dict.
  """
  def encode(dict, encoder \\ &to_string/1) do
    encode_pair(nil, dict, encoder)
  end

  # covers maps
  defp encode_pair(parent_field, dict, encoder) when is_map(dict) do
    encode_dict(dict, parent_field, encoder)
  end

  # covers keyword lists
  defp encode_pair(parent_field, list, encoder) when is_list(list) and is_tuple(hd(list)) do
    encode_dict(Enum.uniq(list, &elem(&1, 0)), parent_field, encoder)
  end

  # covers non-keyword lists
  defp encode_pair(parent_field, list, encoder) when is_list(list) do
    Enum.map_join list, "&", &encode_pair("#{parent_field}[]", &1, encoder)
  end

  defp encode_pair(field, value, encoder) do
    field <> "=" <> encode_value(value, encoder)
  end

  defp encode_dict(dict, parent_field, encoder) do
    Enum.map_join(dict, "&", fn {field, value} ->
      field =
        if parent_field do
          "#{parent_field}[#{encode_key(field)}]"
        else
          encode_key(field)
        end
      encode_pair(field, value, encoder)
    end)
  end

  defp encode_key(item) do
    item |> to_string |> URI.encode_www_form
  end

  defp encode_value(item, encoder) do
    item |> encoder.() |> URI.encode_www_form
  end
end
