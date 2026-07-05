defmodule Notex.MCP.Server do
  @moduledoc """
  Minimal stateless MCP JSON-RPC adapter for the local notebook.
  """

  alias Notex.Notebooks

  @protocol_version "2025-11-25"

  def handle(%{"jsonrpc" => "2.0", "method" => method} = request) do
    id = Map.get(request, "id")

    case dispatch(method, Map.get(request, "params", %{})) do
      {:ok, result} -> response(id, result)
      {:tool_error, message} -> response(id, tool_error(message))
      {:error, code, message} -> error(id, code, message)
    end
  end

  def handle(_request), do: error(nil, -32600, "Invalid JSON-RPC request")

  defp dispatch("initialize", _params) do
    {:ok,
     %{
       protocolVersion: @protocol_version,
       capabilities: %{
         tools: %{listChanged: false},
         resources: %{listChanged: false}
       },
       serverInfo: %{
         name: "notex",
         title: "Notex Notebook MCP",
         version: "0.1.0"
       },
       instructions:
         "Use Notex tools to add local sources, search notebook evidence, and draft cited answers."
     }}
  end

  defp dispatch("ping", _params), do: {:ok, %{}}

  defp dispatch("tools/list", _params), do: {:ok, %{tools: tools()}}

  defp dispatch("tools/call", %{"name" => name} = params) do
    call_tool(name, Map.get(params, "arguments", %{}))
  end

  defp dispatch("tools/call", _params), do: {:error, -32602, "Missing tool name"}

  defp dispatch("resources/list", _params), do: {:ok, %{resources: Notebooks.list_resources()}}

  defp dispatch("resources/read", %{"uri" => uri}) do
    case Notebooks.read_resource(uri) do
      {:ok, resource} -> {:ok, %{contents: [resource]}}
      {:error, :not_found} -> {:error, -32602, "Unknown resource URI"}
    end
  end

  defp dispatch("resources/read", _params), do: {:error, -32602, "Missing resource URI"}

  defp dispatch("notifications/initialized", _params), do: {:ok, %{}}

  defp dispatch(method, _params), do: {:error, -32601, "Method not found: #{method}"}

  defp call_tool("notex.list_notebooks", _args) do
    notebooks =
      Notebooks.list_notebooks()
      |> Enum.map(&%{id: &1.id, title: &1.title, description: &1.description})

    {:ok, structured(%{notebooks: notebooks})}
  end

  defp call_tool("notex.llm_status", _args) do
    {:ok, structured(%{llm: Notebooks.llm_status()})}
  end

  defp call_tool("notex.add_source", %{"title" => title, "body" => body} = args) do
    notebook = notebook_from_args(args)

    case Notebooks.add_source(notebook, %{title: title, body: body}) do
      {:ok, source} ->
        {:ok,
         structured(%{
           source: %{
             id: source.id,
             notebook_id: source.notebook_id,
             title: source.title,
             word_count: source.word_count,
             chunks: length(source.chunks)
           }
         })}

      {:error, changeset} ->
        {:tool_error, changeset_errors(changeset)}
    end
  end

  defp call_tool("notex.add_source", _args), do: {:tool_error, "title and body are required"}

  defp call_tool("notex.search", %{"query" => query} = args) do
    notebook = notebook_from_args(args)
    limit = Map.get(args, "limit", 6)
    matches = Notebooks.search(notebook, query, limit: limit)
    result = %{matches: Enum.map(matches, &tool_match/1)}
    maybe_record_tool_exchange(args, notebook, tool_query("notex.search", query), result)

    {:ok, structured(result)}
  end

  defp call_tool("notex.search", _args), do: {:tool_error, "query is required"}

  defp call_tool("notex.answer", %{"question" => question} = args) do
    notebook = notebook_from_args(args)

    case mcp_answer(notebook, question, args) do
      {:ok, result} ->
        {:ok,
         structured(%{
           answer: result.answer,
           citations: result.citations,
           llm: result.llm,
           matches: Enum.map(result.matches, &tool_match/1)
         })}

      {:error, :empty_question} ->
        {:tool_error, "question cannot be empty"}

      {:error, :no_evidence} ->
        {:tool_error, "Select a source."}

      {:error, {:llm_unavailable, :no_evidence}} ->
        {:tool_error, "Select a source."}

      {:error, {:llm_unavailable, reason}} ->
        {:tool_error, "Chat failed: #{format_llm_reason(reason)}"}

      {:error, changeset} ->
        {:tool_error, changeset_errors(changeset)}
    end
  end

  defp call_tool("notex.answer", _args), do: {:tool_error, "question is required"}

  defp call_tool(name, _args), do: {:error, -32602, "Unknown tool: #{name}"}

  defp mcp_answer(notebook, question, %{"record_chat" => false}) do
    with {:ok, %{matches: matches, citations: citations}} <-
           Notebooks.local_question_context(notebook, question),
         {:ok, answer, llm} <- Notebooks.synthesize_question(question, matches) do
      {:ok, %{answer: answer, citations: citations, llm: llm, matches: matches}}
    end
  end

  defp mcp_answer(notebook, question, _args), do: Notebooks.ask_question(notebook, question)

  defp notebook_from_args(%{"notebook_id" => id}) when id not in [nil, ""] do
    Notebooks.get_notebook!(id)
  end

  defp notebook_from_args(_args), do: Notebooks.get_default_notebook()

  defp tool_query("notex.search", query), do: "notex.search: #{query}"
  defp tool_query("notex.answer", question), do: "notex.answer: #{question}"

  defp maybe_record_tool_exchange(%{"record_chat" => false}, _notebook, _query, _result), do: :ok

  defp maybe_record_tool_exchange(_args, notebook, query, result) do
    Notebooks.record_tool_exchange(notebook, query, Jason.encode!(result))
  end

  defp tools do
    [
      %{
        name: "notex.list_notebooks",
        title: "List Notebooks",
        description: "List local Notex notebooks.",
        inputSchema: empty_schema()
      },
      %{
        name: "notex.llm_status",
        title: "LLM Status",
        description: "Show whether GPT-5.5 low answer synthesis is configured.",
        inputSchema: empty_schema()
      },
      %{
        name: "notex.add_source",
        title: "Add Source",
        description: "Add source text to a notebook and chunk it for retrieval.",
        inputSchema: %{
          type: "object",
          properties: %{
            notebook_id: %{type: "integer"},
            title: %{type: "string"},
            body: %{type: "string"}
          },
          required: ["title", "body"]
        }
      },
      %{
        name: "notex.search",
        title: "Search Notebook",
        description: "Search notebook source chunks and return cited evidence.",
        inputSchema: %{
          type: "object",
          properties: %{
            notebook_id: %{type: "integer"},
            query: %{type: "string"},
            limit: %{type: "integer", minimum: 1, maximum: 20}
          },
          required: ["query"]
        }
      },
      %{
        name: "notex.answer",
        title: "Draft Cited Answer",
        description: "Draft a source-grounded answer from notebook evidence.",
        inputSchema: %{
          type: "object",
          properties: %{
            notebook_id: %{type: "integer"},
            question: %{type: "string"}
          },
          required: ["question"]
        }
      }
    ]
  end

  defp empty_schema, do: %{type: "object", additionalProperties: false}

  defp structured(data) do
    %{
      content: [%{type: "text", text: Jason.encode!(data)}],
      structuredContent: data,
      isError: false
    }
  end

  defp tool_error(message) do
    %{
      content: [%{type: "text", text: message}],
      isError: true
    }
  end

  defp tool_match(match) do
    %{
      chunk_id: match.chunk_id,
      source_id: match.source_id,
      source_title: match.source_title,
      position: match.position,
      score: match.score,
      excerpt: match.excerpt
    }
  end

  defp format_llm_reason(reason), do: inspect(reason)

  defp changeset_errors(changeset) do
    changeset.errors
    |> Enum.map_join(", ", fn {field, {message, _opts}} -> "#{field} #{message}" end)
  end

  defp response(id, result), do: %{jsonrpc: "2.0", id: id, result: result}

  defp error(id, code, message) do
    %{jsonrpc: "2.0", id: id, error: %{code: code, message: message}}
  end
end
