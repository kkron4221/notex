defmodule NotexWeb.MCPController do
  use NotexWeb, :controller

  alias Notex.MCP.Server

  def info(conn, _params) do
    json(conn, %{
      name: "notex",
      transport: "http-json-rpc",
      endpoint: "/mcp",
      protocolVersion: "2025-11-25"
    })
  end

  def rpc(conn, payload) when is_list(payload) do
    json(conn, Enum.map(payload, &Server.handle/1))
  end

  def rpc(conn, payload) when is_map(payload) do
    json(conn, Server.handle(payload))
  end

  def rpc(conn, _payload) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      jsonrpc: "2.0",
      id: nil,
      error: %{code: -32600, message: "Invalid JSON-RPC request"}
    })
  end
end
