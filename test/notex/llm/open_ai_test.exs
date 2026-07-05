defmodule Notex.LLM.OpenAITest do
  use ExUnit.Case, async: true

  alias Notex.LLM.OpenAI

  test "sends a GPT-5.5 low Responses API request and extracts output_text" do
    requester = fn url, headers, payload ->
      send(self(), {:request, url, headers, payload})
      {:ok, %{status: 200, body: %{"output_text" => "Answer from GPT [1]"}}}
    end

    matches = [
      %{
        source_title: "Launch notes",
        position: 0,
        excerpt: "Support risk is highest during migration."
      }
    ]

    assert {:ok, "Answer from GPT [1]", %{"model" => "gpt-5.5", "reasoning_effort" => "low"}} =
             OpenAI.synthesize("Where is support risk highest?", matches,
               api_key: "test-key",
               requester: requester
             )

    assert_receive {:request, "https://api.openai.com/v1/responses", headers, payload}
    assert {"authorization", "Bearer test-key"} in headers
    assert payload.model == "gpt-5.5"
    assert payload.reasoning.effort == "low"
    assert payload.input =~ "Support risk is highest during migration."
  end

  test "reports not configured without an API key for remote OpenAI" do
    assert {:error, :not_configured} =
             OpenAI.synthesize("Question?", [%{source_title: "A", position: 0, excerpt: "B"}],
               api_key: nil,
               base_url: "https://api.openai.com/v1"
             )
  end
end
