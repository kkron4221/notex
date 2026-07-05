defmodule Notex.Notebooks.SourceChunk do
  @moduledoc false

  defstruct [
    :id,
    :source_id,
    :notebook_id,
    :position,
    :content,
    :inserted_at,
    :updated_at,
    word_count: 0
  ]
end
