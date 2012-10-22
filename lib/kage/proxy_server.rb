require 'em-proxy'
require 'kage/connection'

module Kage
  class ProxyServer < ::Proxy
    attr_accessor :host, :port, :debug, :client_timeout, :backend_timeout, :backends, :master, :callbacks

    def initialize(options = {})
      @host = '0.0.0.0'
      @port = 80
      @debug = false
      @client_timeout = 15
      @backend_timeout = 30
      @backends = {}
      @master = nil
      @callbacks = {}

      options.each do |k, v|
        send("#{k}=", v)
      end
    end

    def on_select_backends(&blk); @callbacks[:on_select_backends] = blk; end
    def on_munge_headers(&blk); @callbacks[:on_munge_headers] = blk; end
    def on_backends_finished(&blk); @callbacks[:on_backends_finished] = blk; end

    def add_master_backend(name, host, port = 80)
      @master = name
      add_backend(name, host, port)
    end

    def add_backend(name, host, port = 80)
      @backends[name] = {:host => host, :port => port}
    end

    def self.start(options = {}, &blk)
      server = new(options)
      server.instance_eval &blk

      if server.master.nil?
        raise "Configuration error: no master backend defined"
      end

      super(:host => server.host, :port => server.port, :debug => server.debug) do |conn|
        conn.extend Connection
        conn.handle(server)
      end
    end
  end
end
