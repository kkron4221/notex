defmodule Notex.LLM do
  @moduledoc """
  LLM boundary for source-grounded answer synthesis.
  """

  alias Notex.LLM.{CodexAppServer, Disabled, OpenAI}

  @callback synthesize(String.t(), list(map()), keyword()) ::
              {:ok, String.t(), map()} | {:error, term()}

  def synthesize(question, matches, opts \\ []) do
    provider().synthesize(question, matches, opts)
  end

  def synthesize_stream(question, matches, opts \\ []) do
    provider = provider()

    if Code.ensure_loaded?(provider) and function_exported?(provider, :synthesize_stream, 3) do
      provider.synthesize_stream(question, matches, opts)
    else
      provider.synthesize(question, matches, opts)
    end
  end

  def status do
    provider_status(provider())
  end

  defp provider do
    case System.get_env("NOTEX_LLM_PROVIDER") do
      "codex_app_server" -> CodexAppServer
      "openai" -> OpenAI
      "disabled" -> Disabled
      _other -> configured_provider()
    end
  end

  defp configured_provider do
    :notex
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:provider, CodexAppServer)
  end

  defp provider_status(provider) do
    if Code.ensure_loaded?(provider) and function_exported?(provider, :status, 0) do
      provider.status()
    else
      %{provider: inspect(provider), configured?: true}
    end
  end
end
