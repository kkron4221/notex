defmodule Notex.Support.LLMStub do
  @behaviour Notex.LLM

  @impl true
  def synthesize(_question, _matches, _opts) do
    {:ok, "Stubbed LLM answer from the provided evidence [1]",
     %{"provider" => "stub", "model" => "stub", "reasoning_effort" => "low"}}
  end

  def status do
    %{
      provider: "stub",
      model: "stub",
      reasoning_effort: "low",
      configured?: true
    }
  end
end
