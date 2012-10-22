# Kage

Kage (kah-geh) is an HTTP shadow proxy server that sits between clients and your server(s) to enable "shadow requests".

Kage can be used to duplex requests to the master (production) server and shadow servers that have newer code changes that are going to be deployed. By shadowing requests to the new code you can make sure there are no big/surprising changes in the response in terms of data, performance and database loads etc.

You can customize the behavior of Kage with simple callbacks, when it chooses which backends to send shadow requests to (or not at all), appends or deletes HTTP headers per backend, and examines the complete HTTP response (including headers and body).

## Features

* Support HTTP/1.0 and HTTP/1.1 with partial keep-alive support (See below)
* Callback to decide backends per request URLs
* Callback to manipulate request headers per request and backend
* Callback to examine responses from multiple backends (e.g. calcurate diffs)

Kage does not yet support:

* SSL
* HTTP/1.1 requests pipelining

## Usage

```ruby
require 'kage'

def compare(a, b)
  p [a, b]
end

Kage::ProxyServer.start do |server|
  server.port = 8090
  server.host = '0.0.0.0'
  server.debug = false

  # backends can share the same host/port
  server.add_master_backend(:production, 'localhost', 80)
  server.add_backend(:sandbox, 'localhost', 80)

  server.client_timeout = 15
  server.backend_timeout = 10

  # Dispatch all GET requests to multiple backends, otherwise only :production
  server.on_select_backends do |request, headers|
    if request[:method] == 'GET'
      [:production, :sandbox]
    else
      [:production]
    end
  end

  # Add optional headers
  server.on_munge_headers do |backend, headers|
    headers['X-Kage-Session'] = self.session_id
    headers['X-Kage-Sandbox'] = 1 if backend == :sandbox
  end

  # This callback is only fired when there are multiple backends to respond
  server.on_backends_finished do |backends, requests, responses|
    compare(responses[:production][:data], responses[:sandbox][:data])
  end
end
```

Read more sample code under the `examples/` directory.

## Keep-alives

Kage supports keep-alives for single backend requests, i.e. for requests where `on_select_backends` returns only the master backend.

To make `on_backend_finished` callback simpler, if the current request matches with multiple backends, Kage sends `Connection: close` to the backends so that the callback will only get one response per backend in `responses` hash, which would look like:

```ruby
responses = {
  :original => {:data => "(RAW HTTP response)", :elapsed => 0.1234},
  :sandbox  => {:data => "(RAW HTTP response)", :elapsed => 0.2333},
}
```

## Authors

Tatsuhiko Miyagawa, Yusuke Mito

## Acknowledgements

Ilya Grigorik, Jos Boumans

## Based On

* [EventMachine](http://rubyeventmachine.com/)
* [em-proxy](https://github.com/igrigorik/em-proxy/)
* [http_parser.rb](https://github.com/tmm1/http_parser.rb)
