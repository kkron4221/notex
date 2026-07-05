defmodule Notex.LLM.Disabled do
  @behaviour Notex.LLM

  @impl true
  def synthesize(_question, _matches, _opts), do: {:error, :disabled}

  def status do
    %{
      provider: "disabled",
      model: "gpt-5.5",
      reasoning_effort: "low",
      configured?: false
    }
  end
end
