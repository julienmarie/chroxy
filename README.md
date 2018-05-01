# Chroxy

Scalable Chrome Browser RDP Session Service.

* Provides connections to Chrome Browser Pages via WebSocket connection.
* Manages Chrome Browser process via Erlang processes using `erlexec`
  * OS Process supervision and resiliency through automatic restart on crash.
* Uses Chrome Remote Debugging Protocol for optimal client compatibility.
* Transparent Dynamic Proxy provides automatic resource cleanup.

The objective of this project is to enable connections to headless chrome
instances with minimal overhead and abstractions.  Unlike browser testing
frameworks such as Hound and Wallaby, Chroxy aims to provide direct unfettered
access to the underlying browser using the [Chrome Remote Debug
protocol](https://chromedevtools.github.io/devtools-protocol/) whilst
enabling many 1000s of concurrently executing tests.

Chroxy uses Elixir processes and OTP supervision to manage the chrome instances,
as well as including a transparent proxy to facilitate automatic initialisation
and termination of the underlying chrome page based on the upstream connection
lifetime.

This project was born out of necessity and is in its infancy.

### Components

#### Proxy

A intermediary TCP proxy is in place to allow for monitoring of the _upstream_
client and _downstream_ chrome RSP web socket connections, in order to cleanup
resources after connections are closed.

`ProxyListener` - Incoming Connection Management & Delegation
* Listens for incoming connections on a given PORT.
* Exposes `accept/1` function which will accept the next _upstream_ TCP connection and
  delegate the connection to a `ProxyServer` process along with the `proxy_opts`
  which enable dynamic configuration of the _downstream_ connection.

`ProxyServer` - Dynamically Configured Transparent Proxy
* A dynamically configured transparent proxy.
* Manages delegated connection as the _upstream_ connection.
* Establishes _downstream_ connection based on `proxy_opts` or
  `ProxyServer.Hook.up/2` hook modules response, at initialisation.

`ProxyServer.Hook` - Behaviour for `ProxyServer` hooks. Example: `ChromeProxy`
* A mechanism by which a module / server can be invoked when a `ProxyServer`
  process is coming _up_ or _down_.
* Two _optional_ callbacks can be implemented:
  * `@spec up(indentifier(), proxy_opts()) :: proxy_opts()`
    * provides the registered process with option to add or change proxy
      options prior to downstream connection initialisation.
  * `@spec down(indentifier(), proxy_state) :: :ok`
    * provides the registered process with signal that the proxy connection is
      about to terminate, due to either _upstream_ or _downstream_ connections
      closing.

#### Chrome Browser Management

Chrome is the first browser supported, and the following server processes manage
the communication and lifetime of the Chrome Browsers and Tabs.

`ChromeProxy` - Implements `ProxyServer.Hook` for Chrome resource management
* Exposes function `connection/1` which returns the websocket connection to the
  browser tab, with the proxy host and port substituted in order to route the
  connection via the underlying `ProxyServer` process.
* Registers for callbacks from the underlying `ProxyServer`, implementing the
  `down/2` callback in order to cleanup the Chrome resource when connections
  close.

`ChromeServer` - Wraps Chrome Browser OS Process
* Process which manages execution and control of a Chrome Browser OS process.
* Provides basic API wrapper to manage the required browser level functionality
  around page creation, access and closing.
* Translates browser logging to elixir logging, with correct levels.

`ChromeManager` - Inits & Controls access to pool of `ChromeServer` processes
* Manages `ChromeServer` process pool, responsible for spawning a browser
  process for each defined PORT in the port range configured.
* Exposes `connection/0` function which will return a WebSocket connection to a
  browser tab, from a random browser process in the managed pool.

#### `Endpoint` - HTTP API

`GET /api/v1/connection`

Returns WebSocket URI `ws://` to a Chrome Browser Page which is routed via the
Proxy.  The first port of call for external client connecting to the service.

Request:
```
$ curl http://localhost:1330/api/v1/connection
```
Response:
```
ws://localhost:1331/devtools/page/2CD7F0BC05863AB665D1FB95149665AF
```

### Configuration

The configuration is designed to be friendly for containerisation as such uses
environment variables.

If using Chroxy from within another OTP application you may wish to leverage the
configuration implementation of Chroxy by including the config like so in your
`config/config.exs` file:

```
include_config "../deps/chroxy/config/config.exs"
```

Ports, Proxy Host and Endpoint Scheme are managed via Env Vars.

| Variable                          | Default       | Desc.                                                      |
| :------------------------         | :------------ | :--------------------------------------------------------- |
| CHROXY_CHROME_PORT_FROM           | 9222          | Starting port in the Chrome Browser port range             |
| CHROXY_CHROME_PORT_TO             | 9223          | Last port in the Chrome Browser port range                 |
| CHROXY_PROXY_HOST                 | "127.0.0.1"   | Host which is substituted to route connections via proxy   |
| CHROXY_PROXY_PORT                 | 1331          | Port which proxy listener will accept connections on       |
| CHROXY_ENDPOINT_SCHEME            | :http         | `HTTP` or `HTTPS`                                          |
| CHROXY_ENDPOINT_PORT              | 1330          | HTTP API will register on this port                        |
| CHROXY_CHROME_SERVER_PAGE_WAIT_MS | 50            | Milliseconds to wait after asking chrome to create a page  |

### Operation Examples

See: https://github.com/holsee/chroxy_client
``` elixir
# Establish 100 connections
clients = Enum.map(1..100, fn(_) ->
  ChroxyClient.page_session!(%{host: "localhost", port: 1330})
end)
```

``` elixir
# Run 100 Asynchronous browser operations
Task.async_stream(clients, fn(client) ->
  url = "https://github.com/holsee"
  {:ok, _} = ChromeRemoteInterface.RPC.Page.navigate(client, %{url: url})
end, timeout: :infinity) |> Stream.run
```
