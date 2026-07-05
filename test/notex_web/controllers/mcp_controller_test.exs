defmodule NotexWeb.MCPControllerTest do
  use NotexWeb.ConnCase

  setup do
    old_config = Application.get_env(:notex, Notex.LLM)

    Application.put_env(
      :notex,
      Notex.LLM,
      Keyword.put(old_config, :provider, Notex.Support.LLMStub)
    )

    on_exit(fn -> Application.put_env(:notex, Notex.LLM, old_config) end)
  end

  test "initializes and lists tools", %{conn: conn} do
    conn =
      post(conn, ~p"/mcp", %{
        jsonrpc: "2.0",
        id: 1,
        method: "initialize",
        params: %{}
      })

    assert %{"result" => %{"protocolVersion" => "2025-11-25"}} = json_response(conn, 200)

    conn =
      post(build_conn(), ~p"/mcp", %{
        jsonrpc: "2.0",
        id: 2,
        method: "tools/list",
        params: %{}
      })

    assert %{"result" => %{"tools" => tools}} = json_response(conn, 200)
    assert Enum.any?(tools, &(&1["name"] == "notex.answer"))
  end

  test "adds a source and answers through tools", %{conn: conn} do
    notebook = Notex.Notebooks.get_default_notebook()

    conn =
      post(conn, ~p"/mcp", %{
        jsonrpc: "2.0",
        id: 1,
        method: "tools/call",
        params: %{
          name: "notex.add_source",
          arguments: %{
            title: "Strategy excerpt",
            body:
              "Enterprise buyers asked for audit trails. The roadmap should prioritize audit trails."
          }
        }
      })

    assert %{
             "result" => %{"structuredContent" => %{"source" => %{"title" => "Strategy excerpt"}}}
           } =
             json_response(conn, 200)

    conn =
      post(build_conn(), ~p"/mcp", %{
        jsonrpc: "2.0",
        id: 2,
        method: "tools/call",
        params: %{
          name: "notex.answer",
          arguments: %{question: "What should the roadmap prioritize?"}
        }
      })

    assert %{
             "result" => %{"structuredContent" => %{"answer" => answer, "citations" => citations}}
           } =
             json_response(conn, 200)

    assert answer =~ "Stubbed LLM answer"
    assert map_size(citations) > 0

    [source_added_user, source_added_assistant] = Notex.Notebooks.list_messages(notebook)
    assert source_added_user.content == "What should the roadmap prioritize?"
    assert source_added_assistant.content =~ "Stubbed LLM answer"
  end

  test "records MCP search query and result as chat messages", %{conn: conn} do
    notebook = Notex.Notebooks.get_default_notebook()

    {:ok, _source} =
      Notex.Notebooks.add_source(notebook, %{
        title: "Searchable source",
        body: "Searchable source body mentions audit trails and roadmap evidence."
      })

    conn =
      post(conn, ~p"/mcp", %{
        jsonrpc: "2.0",
        id: 1,
        method: "tools/call",
        params: %{
          name: "notex.search",
          arguments: %{query: "audit trails"}
        }
      })

    assert %{"result" => %{"structuredContent" => %{"matches" => [_match | _]}}} =
             json_response(conn, 200)

    [user_message, assistant_message] = Notex.Notebooks.list_messages(notebook)
    assert user_message.role == "user"
    assert user_message.content == "notex.search: audit trails"
    assert assistant_message.role == "assistant"
    assert assistant_message.content =~ "Searchable source"
  end

  test "returns tool error with the answer synthesis failure reason", %{conn: conn} do
    old_config = Application.get_env(:notex, Notex.LLM)
    Application.put_env(:notex, Notex.LLM, Keyword.put(old_config, :provider, Notex.LLM.Disabled))

    conn =
      post(conn, ~p"/mcp", %{
        jsonrpc: "2.0",
        id: 1,
        method: "tools/call",
        params: %{
          name: "notex.add_source",
          arguments: %{
            title: "Strategy excerpt",
            body: "The roadmap should prioritize audit trails."
          }
        }
      })

    assert %{"result" => %{"isError" => false}} = json_response(conn, 200)

    conn =
      post(build_conn(), ~p"/mcp", %{
        jsonrpc: "2.0",
        id: 2,
        method: "tools/call",
        params: %{
          name: "notex.answer",
          arguments: %{question: "What should the roadmap prioritize?"}
        }
      })

    assert %{"result" => %{"isError" => true, "content" => [%{"text" => message}]}} =
             json_response(conn, 200)

    assert message == "Chat failed: :disabled"
    refute message =~ "LLM synthesis unavailable"
    refute message =~ "no_evidence"
  end
end
