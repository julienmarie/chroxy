defmodule Chroxy.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  require Logger

  def start(_type, _args) do
    # HACK to get exec running as root.
    Application.put_env(:exec, :root, true)
    Application.put_env(:exec, :port_path, "/usr/local/bin/exec-port")
    Application.put_env(:exec, :portexe, '/usr/local/bin/exec-port')
    
    IO.inspect :exec.start(portexe: '/usr/local/bin/exec-port')

    # {:ok, _} = Application.ensure_all_started(:erlexec)
    # {:ok, _} = Application.ensure_all_started(:exexec)


    proxy_opts = Application.get_env(:chroxy, Chroxy.ProxyListener)

    children = [
      Chroxy.ProxyListener.child_spec(proxy_opts),
      Chroxy.ChromeServer.Supervisor.child_spec(),
      Chroxy.BrowserPool.child_spec(),
      Chroxy.Endpoint.child_spec(),
      Chroxy.ProxyRouter.child_spec()
    ]

    Logger.info("Started application")

    opts = [strategy: :one_for_one, name: Chroxy.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
