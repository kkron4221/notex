defmodule Notex.Notebooks.Message do
  @moduledoc false

  defstruct [
    :id,
    :role,
    :content,
    :notebook_id,
    :inserted_at,
    :updated_at,
    citations: %{}
  ]
end
