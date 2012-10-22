require 'http/parser'

module Kage
  module Connection
    attr_accessor :master_backend, :session_id

    # http://eventmachine.rubyforge.org/EventMachine/Connection.html#unbind-instance_method
    def close_connection(*args)
      @server_side_close = true
      super
    end

    def unbind
      if !@server_side_close
        if @state == :request
          info "Client disconnected in the request phase"
          super
        elsif @backends && @backends.size == 1 && @responses[master_backend]
          info "Client disconnected after the master response. Closing master"
          super
        else
          info "Client disconnected. Waiting for all backends to finish"
        end
      end
    end

    def cleanup!
      @parser.reset!
    end

    def all_servers_finished?
      @servers.values.compact.size.zero?
    end

    def callback(cb, *args)
      if @callbacks[cb]
        instance_exec *args, &@callbacks[cb]
      elsif block_given?
        yield
      end
    rescue Exception => e
      info "#{e} - #{e.backtrace}"
    end

    def build_headers(parser, headers)
      "#{parser.http_method} #{parser.request_url} HTTP/#{parser.http_version.join(".")}\r\n" +
      headers.map{|k, v| "#{k}: #{v}\r\n" }.join('') +
      "\r\n"
    end

    def connect_backends!(req, headers, backends)
      @backends = select_backends(req, headers, backends).select {|b| backends[b]}
      @backends.unshift master_backend unless @backends.include? master_backend
      info "Backends for #{req[:method]} #{req[:url]} -> #{@backends}"

      @backends.each do |name|
        s = server name, backends[name]
        s.comm_inactivity_timeout = 10
      end
    end

    def select_backends(request, headers, backends)
      callback(:on_select_backends, request, headers) { backends.keys }
    end

    def handle(server)
      self.comm_inactivity_timeout = server.client_timeout
      self.master_backend = server.master

      @session_id = "%016x" % Random.rand(2**64)
      info "New connection"

      @callbacks = server.callbacks

      @responses = {}
      @request = {}
      @requests = []

      @state = :request

      @parser = HTTP::Parser.new
      @parser.on_message_begin = proc do
        @start_time ||= Time.now
        @state = :request
      end

      @parser.on_headers_complete = proc do |headers|
        @request = {
          :method => @parser.http_method,
          :path => @parser.request_path,
          :url => @parser.request_url,
          :headers => headers
        }
        @requests.push @request
        info "#{@request[:method]} #{@request[:url]}"

        # decide backends on the first request
        unless @backends
          connect_backends!(@request, headers, server.backends)
        end

        if @backends.size > 1
          info "Multiple backends for this session: Force close connection (disable keep-alives)"
          headers['Connection'] = 'close'
        end

        @servers.keys.each do |backend|
          callback :on_munge_headers, backend, headers
          relay_to_servers [build_headers(@parser, headers), [backend]]
        end
      end

      @parser.on_body = proc do |chunk|
        relay_to_servers chunk
      end

      @parser.on_message_complete = proc do
        @state = :response
      end

      on_data do |data|
        begin
          @parser << data
        rescue HTTP::Parser::Error
          info "HTTP parser error: Bad Request"
          EM.next_tick { close_connection_after_writing }
        end
        nil
      end

      # modify / process response stream
      on_response do |backend, resp|
        @responses[backend] ||= {}
        @responses[backend][:elapsed] = Time.now.to_f - @start_time.to_f
        @responses[backend][:data] ||= ''
        @responses[backend][:data] += resp

        resp if backend == master_backend
      end

      # termination logic
      on_finish do |backend|
        # terminate connection (in duplex mode, you can terminate when prod is done)
        if all_servers_finished?
          if @backends.all? {|b| @responses[b]}
            callback :on_backends_finished, @backends, @requests, @responses if @backends.size > 1
          else
            info "Server(s) disconnected before response returned: #{@backends.reject {|b| @responses[b]}}"
          end
          cleanup!
        end

        if backend == master_backend
          info "Master backend closed connection. Closing downstream"
          :close
        end
      end
    rescue Exception => e
      info "#{e} - #{e.backtrace}"
    end

    def info(msg)
      puts "#{Time.now.strftime('%H:%M:%S')} [#{@session_id}] #{msg}"
    end
  end
end

