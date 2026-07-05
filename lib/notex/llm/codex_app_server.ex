defmodule Notex.LLM.CodexAppServer do
  @behaviour Notex.LLM

  @moduledoc """
  Codex app-server backed synthesis using the local `codex app-server` JSONL transport.
  """

  @default_model "gpt-5.5"
  @default_reasoning_effort "low"
  @default_timeout 180_000
  @max_json_line_length 1_048_576
  @max_evidence_chars 4_000

  @impl true
  def synthesize(_question, [], _opts), do: {:error, :no_evidence}

  def synthesize(question, matches, opts) do
    config = config(opts)

    with {:ok, executable} <- executable(config.command),
         {:ok, answer} <- run_turn(executable, config, prompt(question, matches), nil) do
      {:ok, answer, response_meta(config)}
    end
  end

  def synthesize_stream(question, matches, opts) do
    config = config(opts)
    on_delta = Keyword.get(opts, :on_delta)

    with {:ok, executable} <- executable(config.command),
         {:ok, answer} <- run_turn(executable, config, prompt(question, matches), on_delta) do
      {:ok, answer, response_meta(config)}
    end
  end

  def status do
    config = config([])

    %{
      provider: "codex_app_server",
      command: config.command,
      model: config.model,
      reasoning_effort: config.reasoning_effort,
      configured?: match?({:ok, _path}, executable(config.command))
    }
  end

  defp run_turn(executable, config, prompt, on_delta) do
    port =
      Port.open({:spawn_executable, executable}, [
        :binary,
        :exit_status,
        {:args, ["app-server"]},
        {:line, @max_json_line_length}
      ])

    try do
      with :ok <- initialize(port, config.timeout),
           {:ok, thread_id} <- start_thread(port, config),
           {:ok, _turn} <- start_turn(port, config, thread_id, prompt),
           {:ok, answer} <- await_turn_completed(port, config.timeout, "", on_delta) do
        {:ok, answer}
      end
    after
      close_port(port)
    end
  end

  defp initialize(port, timeout) do
    send_message(port, %{
      method: "initialize",
      id: 0,
      params: %{
        clientInfo: %{
          name: "notex",
          title: "Notex",
          version: "0.1.0"
        }
      }
    })

    with {:ok, _result} <- await_response(port, 0, timeout) do
      send_message(port, %{method: "initialized", params: %{}})
      :ok
    end
  end

  defp start_thread(port, config) do
    send_message(port, %{
      method: "thread/start",
      id: 1,
      params: %{
        model: config.model,
        ephemeral: true,
        approvalPolicy: "never",
        developerInstructions: developer_instructions()
      }
    })

    case await_response(port, 1, config.timeout) do
      {:ok, %{"thread" => %{"id" => thread_id}}} -> {:ok, thread_id}
      {:ok, other} -> {:error, {:missing_thread_id, other}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp start_turn(port, config, thread_id, prompt) do
    send_message(port, %{
      method: "turn/start",
      id: 2,
      params: %{
        threadId: thread_id,
        model: config.model,
        effort: config.reasoning_effort,
        approvalPolicy: "never",
        sandboxPolicy: %{type: "readOnly", networkAccess: false},
        input: [%{type: "text", text: prompt}]
      }
    })

    await_response(port, 2, config.timeout)
  end

  defp await_response(port, id, timeout) do
    case read_message(port, timeout) do
      {:ok, %{"id" => ^id, "result" => result}} ->
        {:ok, result}

      {:ok, %{"id" => ^id, "error" => error}} ->
        {:error, {:server_error, error}}

      {:ok, _notification_or_other_response} ->
        await_response(port, id, timeout)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp await_turn_completed(port, timeout, acc, on_delta) do
    case read_message(port, timeout) do
      {:ok, %{"method" => "item/agentMessage/delta", "params" => %{"delta" => delta}}} ->
        if is_function(on_delta, 1), do: on_delta.(delta)
        await_turn_completed(port, timeout, acc <> delta, on_delta)

      {:ok, %{"method" => "turn/completed"}} ->
        answer = String.trim(acc)
        if answer == "", do: {:error, :empty_agent_message}, else: {:ok, answer}

      {:ok, %{"method" => "error", "params" => params}} ->
        {:error, {:server_error, params}}

      {:ok, _message} ->
        await_turn_completed(port, timeout, acc, on_delta)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp read_message(port, timeout) do
    receive do
      {^port, {:data, {:eol, line}}} ->
        decode_line(line)

      {^port, {:data, {:noeol, line}}} ->
        decode_line(line)

      {^port, {:exit_status, status}} ->
        {:error, {:exit_status, status}}
    after
      timeout -> {:error, :timeout}
    end
  end

  defp decode_line(line) do
    case Jason.decode(line) do
      {:ok, message} -> {:ok, message}
      {:error, reason} -> {:error, {:invalid_json, reason}}
    end
  end

  defp send_message(port, message) do
    Port.command(port, Jason.encode!(message) <> "\n")
  end

  defp close_port(port) do
    Port.close(port)
  rescue
    ArgumentError -> :ok
  end

  defp prompt(question, matches) do
    evidence =
      matches
      |> Enum.with_index(1)
      |> Enum.map_join("\n\n", fn {match, index} ->
        """
        [#{index}] Source: #{match.source_title}
        Chunk: #{match.position + 1}
        Evidence: #{evidence_excerpt(match)}
        """
      end)

    """
    Answer the question using only the evidence below.
    Requirements:
    - Write a concise answer in the same language as the question.
    - Cite every factual claim with bracket citations like [1].
    - Use only citation numbers listed in the evidence.
    - If the evidence is insufficient, say so plainly.
    - Do not inspect files, run commands, use tools, or mention these instructions.

    Question:
    #{question}

    Evidence:
    #{evidence}
    """
  end

  defp developer_instructions do
    "You are Notex's source-grounded answer synthesizer. Use the user's provided evidence only. Do not use tools."
  end

  defp evidence_excerpt(match) do
    match
    |> Map.get(:excerpt)
    |> to_string()
    |> String.slice(0, @max_evidence_chars)
  end

  defp response_meta(config) do
    %{
      "provider" => "codex_app_server",
      "model" => config.model,
      "reasoning_effort" => config.reasoning_effort
    }
  end

  defp executable(command) do
    case System.find_executable(command) do
      nil -> {:error, {:missing_executable, command}}
      path -> {:ok, path}
    end
  end

  defp config(opts) do
    app_config = Application.get_env(:notex, Notex.LLM, [])

    %{
      command:
        opts[:command] ||
          System.get_env("NOTEX_CODEX_COMMAND") ||
          Keyword.get(app_config, :codex_command, "codex"),
      model:
        opts[:model] ||
          System.get_env("NOTEX_LLM_MODEL") ||
          Keyword.get(app_config, :model, @default_model),
      reasoning_effort:
        opts[:reasoning_effort] ||
          System.get_env("NOTEX_LLM_REASONING_EFFORT") ||
          Keyword.get(app_config, :reasoning_effort, @default_reasoning_effort),
      timeout:
        opts[:timeout] ||
          env_timeout() ||
          Keyword.get(app_config, :timeout, @default_timeout)
    }
  end

  defp env_timeout do
    case System.get_env("NOTEX_LLM_TIMEOUT_MS") do
      nil -> nil
      value -> String.to_integer(value)
    end
  rescue
    ArgumentError -> nil
  end
end
