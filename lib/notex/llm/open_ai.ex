defmodule Notex.LLM.OpenAI do
  @behaviour Notex.LLM

  @moduledoc """
  Responses API-compatible LLM client.
  """

  @default_base_url "https://api.openai.com/v1"
  @default_model "gpt-5.5"
  @default_reasoning_effort "low"

  @impl true
  def synthesize(_question, [], _opts), do: {:error, :no_evidence}

  def synthesize(question, matches, opts) do
    config = config(opts)

    with :ok <- ensure_configured(config),
         {:ok, response} <- request(config, question, matches) do
      {:ok, response, response_meta(config)}
    end
  end

  def status do
    config = config([])

    %{
      provider: "openai_responses",
      base_url: config.base_url,
      model: config.model,
      reasoning_effort: config.reasoning_effort,
      configured?: configured?(config)
    }
  end

  defp request(config, question, matches) do
    payload = payload(config, question, matches)

    headers =
      [{"content-type", "application/json"}] ++
        if config.api_key, do: [{"authorization", "Bearer #{config.api_key}"}], else: []

    case config.requester.(config.base_url <> "/responses", headers, payload) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        body
        |> decode_body()
        |> extract_output_text()

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp payload(config, question, matches) do
    %{
      model: config.model,
      reasoning: %{effort: config.reasoning_effort},
      text: %{verbosity: "low"},
      instructions: instructions(),
      input: input(question, matches)
    }
  end

  defp instructions do
    """
    You answer as Notex, a source-grounded notebook assistant.
    Use only the provided evidence snippets.
    If the evidence does not answer the question, say that the notebook does not contain enough evidence.
    Cite claims with bracketed citation numbers like [1] that correspond exactly to the evidence numbers.
    Keep the answer concise and useful.
    """
  end

  defp input(question, matches) do
    evidence =
      matches
      |> Enum.with_index(1)
      |> Enum.map_join("\n\n", fn {match, index} ->
        """
        [#{index}] Source: #{match.source_title}
        Chunk: #{match.position + 1}
        Evidence: #{match.excerpt}
        """
      end)

    """
    Question:
    #{question}

    Evidence:
    #{evidence}
    """
  end

  defp extract_output_text(%{"output_text" => text}) when is_binary(text), do: {:ok, text}

  defp extract_output_text(%{"output" => output}) when is_list(output) do
    text =
      output
      |> Enum.flat_map(fn
        %{"content" => content} when is_list(content) -> content
        _other -> []
      end)
      |> Enum.map(fn
        %{"type" => "output_text", "text" => text} when is_binary(text) -> text
        %{"text" => text} when is_binary(text) -> text
        _other -> nil
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n")
      |> String.trim()

    if text == "", do: {:error, :missing_output_text}, else: {:ok, text}
  end

  defp extract_output_text(_body), do: {:error, :missing_output_text}

  defp decode_body(body) when is_binary(body), do: Jason.decode!(body)
  defp decode_body(body), do: body

  defp ensure_configured(config) do
    if configured?(config), do: :ok, else: {:error, :not_configured}
  end

  defp configured?(%{api_key: api_key, base_url: base_url}) do
    present?(api_key) or String.starts_with?(base_url, ["http://127.0.0.1", "http://localhost"])
  end

  defp response_meta(config) do
    %{
      "provider" => "openai_responses",
      "model" => config.model,
      "reasoning_effort" => config.reasoning_effort
    }
  end

  defp config(opts) do
    app_config = Application.get_env(:notex, Notex.LLM, [])

    %{
      base_url:
        opts[:base_url] ||
          System.get_env("NOTEX_LLM_BASE_URL") ||
          Keyword.get(app_config, :base_url, @default_base_url),
      api_key:
        opts
        |> option_or_default(:api_key, fn ->
          System.get_env("NOTEX_LLM_API_KEY") ||
            System.get_env("OPENAI_API_KEY") ||
            Keyword.get(app_config, :api_key)
        end)
        |> blank_to_nil(),
      model:
        opts[:model] ||
          System.get_env("NOTEX_LLM_MODEL") ||
          Keyword.get(app_config, :model, @default_model),
      reasoning_effort:
        opts[:reasoning_effort] ||
          System.get_env("NOTEX_LLM_REASONING_EFFORT") ||
          Keyword.get(app_config, :reasoning_effort, @default_reasoning_effort),
      requester:
        opts[:requester] ||
          Keyword.get(app_config, :requester, &__MODULE__.default_requester/3)
    }
  end

  def default_requester(url, headers, payload) do
    Req.post(url, headers: headers, json: payload, receive_timeout: 60_000)
  end

  defp option_or_default(opts, key, default_fun) do
    if Keyword.has_key?(opts, key), do: Keyword.get(opts, key), else: default_fun.()
  end

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end
