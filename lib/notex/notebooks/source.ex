defmodule Notex.Notebooks.Source do
  @moduledoc false

  defstruct [
    :id,
    :title,
    :body,
    :notebook_id,
    :inserted_at,
    :updated_at,
    word_count: 0,
    chunks: []
  ]
end
