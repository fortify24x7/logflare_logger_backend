defmodule LogflareLogger.HttpBackendTest do
  use ExUnit.Case, async: true
  alias LogflareLogger.{HttpBackend, Formatter}
  alias LogflareLogger.ApiClient
  alias Jason, as: JSON
  require Logger

  @port 4444
  @path ApiClient.api_path()

  @logger_backend HttpBackend
  @api_key "l3kh47jsakf2370dasg"
  @source "source2354551"

  setup do
    bypass = Bypass.open(port: @port)
    Application.put_env(:logflare_logger_backend, :url, "http://127.0.0.1:#{@port}")
    Application.put_env(:logflare_logger_backend, :api_key, @api_key)
    Application.put_env(:logflare_logger_backend, :source, @source)
    Application.put_env(:logflare_logger_backend, :level, :info)
    Application.put_env(:logflare_logger_backend, :flush_interval, 500)
    Application.put_env(:logflare_logger_backend, :max_batch_size, 100)

    Logger.add_backend(@logger_backend)

    {:ok, bypass: bypass, config: %{}}
  end

  test "logger backend sends a POST request", %{bypass: bypass, config: config} do
    :ok = Logger.configure_backend(@logger_backend, metadata: [])
    log_msg = "Incoming log from test"
    LogflareLogger.set_context(test_context: %{some_metric: 1337})

    Bypass.expect(bypass, "POST", @path, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      assert {"x-api-key", @api_key} in conn.req_headers

      body = JSON.decode!(body)

      assert %{
               "batch" => [
                 %{
                   "level" => level,
                   "message" => "Incoming log from test " <> _,
                   "context" => %{
                     "metadata" => %{},
                     "test_context" => %{"some_metric" => 1337}
                   },
                   "timestamp" => _
                 }
                 | _
               ],
               "source_name" => @source
             } = body

      assert length(body["batch"]) == 10
      assert level in ["info", "error"]

      Plug.Conn.resp(conn, 200, "")
    end)

    for n <- 1..10, do: Logger.info(log_msg <> " ##{n}")

    Process.sleep(1_000)

    for n <- 1..10, do: Logger.error(log_msg <> " ##{20 + n}")

    Process.sleep(1_000)

    for n <- 1..10, do: Logger.debug(log_msg <> " ##{30 + n}")

    Process.sleep(1_000)
    LogflareLogger.unset_context(:test_context)
  end

  test "doesn't POST log events with a lower level", %{bypass: _bypass, config: config} do
    log_msg = "Incoming log from test"

    :ok = Logger.debug(log_msg)
  end

  @msg "Incoming log from test with all metadata"
  test "correctly handles metadata keys", %{bypass: bypass, config: config} do
    :ok = Logger.configure_backend(@logger_backend, metadata: :all)
    LogflareLogger.set_context(test_context: %{some_metric: 7331})

    Bypass.expect_once(bypass, "POST", @path, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      body = JSON.decode!(body)

      assert %{
               "batch" => [
                 %{
                   "level" => "info",
                   "message" => @msg,
                   "context" => %{
                     "metadata" => %{
                       "pid" => pidbinary,
                       "module" => _,
                       "file" => _,
                       "line" => _,
                       "function" => _
                     },
                     "test_context" => _
                   },
                   "timestamp" => _
                 }
                 | _
               ],
               "source_name" => @source
             } = body

      assert length(body["batch"]) == 45

      Plug.Conn.resp(conn, 200, "")
    end)

    log_msg = @msg

    for n <- 1..45, do: Logger.info(log_msg)

    Process.sleep(1_000)
    LogflareLogger.unset_context(:test_context)
  end
end
