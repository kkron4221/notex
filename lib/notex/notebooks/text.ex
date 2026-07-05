defmodule Notex.Notebooks.Text do
  @moduledoc false

  @chunk_words 120
  @chunk_overlap 24

  def word_count(text) when is_binary(text), do: text |> terms() |> length()
  def word_count(_), do: 0

  def terms(text) when is_binary(text) do
    ~r/[\p{L}\p{N}]+/u
    |> Regex.scan(String.downcase(text))
    |> List.flatten()
    |> Enum.reject(&(String.length(&1) < 2))
  end

  def terms(_), do: []

  def chunks(text) when is_binary(text) do
    words = Regex.scan(~r/\S+/u, String.trim(text)) |> List.flatten()

    words
    |> window_words()
    |> Enum.with_index()
    |> Enum.map(fn {chunk_words, index} ->
      content = Enum.join(chunk_words, " ")

      %{
        position: index,
        content: content,
        word_count: word_count(content)
      }
    end)
  end

  def chunks(_), do: []

  def excerpt(text, terms, radius \\ 180) do
    text = text || ""
    normalized = String.downcase(text)

    index =
      terms
      |> Enum.find_value(fn term ->
        case String.split(normalized, term, parts: 2) do
          [before, _after] -> String.length(before)
          [_unmatched] -> nil
        end
      end)

    start = max((index || 0) - radius, 0)
    excerpt = text |> String.slice(start, radius * 2) |> String.trim()

    cond do
      excerpt == "" -> ""
      start > 0 -> "..." <> excerpt
      true -> excerpt
    end
  end

  defp window_words([]), do: []

  defp window_words(words) do
    step = @chunk_words - @chunk_overlap

    words
    |> Stream.unfold(fn
      [] ->
        nil

      remaining ->
        chunk = Enum.take(remaining, @chunk_words)
        next = Enum.drop(remaining, step)

        if chunk == [] do
          nil
        else
          {chunk, next}
        end
    end)
    |> Enum.to_list()
  end
end
