defmodule Notex.Support.LLMNoEvidenceStub do
  @behaviour Notex.LLM

  @impl true
  def synthesize(_question, _matches, _opts), do: {:error, :no_evidence}

  def status do
    %{
      provider: "no_evidence_stub",
      model: "stub",
      reasoning_effort: "low",
      configured?: true
    }
  end
end
