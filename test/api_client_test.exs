defmodule LogflareLogger.ApiClientTest do
  use ExUnit.Case, async: true
  alias LogflareLogger.ApiClient
  require Logger

  @port 4444
  @path ApiClient.api_path()

  @api_key "l3kh47jsakf2370dasg"
  @source "source2354551"

  setup do
    bypass = Bypass.open(port: @port)

    {:ok, bypass: bypass}
  end

  test "ApiClient sends a correct POST request with gzip in bert format", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", @path, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert {"x-api-key", @api_key} in conn.req_headers

      body =
        body
        |> :zlib.gunzip()
        |> Bertex.safe_decode()

      assert %{
               "batch" => [
                 %{
                   "level" => "info",
                   "message" => "Logger message",
                   "metadata" => %{
                     "file" => "not_existing.ex"
                   }
                 }
               ],
               "source_name" => @source
             } = body

      Plug.Conn.resp(conn, 200, "ok")
    end)

    client = ApiClient.new(%{api_key: @api_key, url: "http://localhost:#{@port}"})

    batch = [
      %{
        "level" => "info",
        "message" => "Logger message",
        "metadata" => %{
          "file" => "not_existing.ex"
        }
      }
    ]

    {:ok, %{body: body}} = ApiClient.post_logs(client, batch, @source)

    assert body == "ok"
  end
end
