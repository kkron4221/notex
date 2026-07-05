defmodule Notex.Notebooks.Notebook do
  @moduledoc false

  defstruct [:id, :title, description: "", inserted_at: nil, updated_at: nil]
end
