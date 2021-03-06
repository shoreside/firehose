module Firehose
  module Rack
    # Acts as the glue between the HTTP/WebSocket world and the Firehose::Server class,
    # which talks directly to the Redis server. Also dispatches between HTTP and WebSocket
    # transport handlers depending on the clients' request.
    class App
      def initialize
        yield self if block_given?
      end

      def call(env)
        # Cache the parsed request so we don't need to re-parse it when we pass
        # control onto another app.
        req     = env['parsed_request'] ||= ::Rack::Request.new(env)
        method  = req.request_method

        case method
        when 'PUT'
          # Firehose::Client::Publisher PUT's payloads to the server.
          publisher.call(env)
        when 'HEAD'
          # HEAD requests are used to prevent sockets from timing out
          # from inactivity
          ping.call(env)
        when 'GET'
          if req.path == '/health/status'
            # if its an authenticated publisher: authentication service healthy?
            publisher.respond_to?(:authentication_service_healthy?) ?
              (publisher.authentication_service_healthy? ?
                healthy_response : not_healthy_response) :
              healthy_response
          else
            consumer.call(env)
          end
        else
          # dont care about other methods
          [400, {}, []]
        end
      end

      def healthy_response
        [200, {'Content-Type' => 'text/plain'}, ['healthy']]
      end

      def not_healthy_response
        [503, {'Content-Type' => 'text/plain'}, ['not healthy']]
      end

      # The consumer pulls messages off of the backend and passes messages to the
      # connected HTTP or WebSocket client. This can be configured from the initialization
      # method of the rack app.
      def consumer
        @consumer ||= Consumer.new
      end

      private
      def publisher
        return @publisher if @publisher
        authentication_uri = ENV['AUTHENTICATION_URI']
        authentication_path = ENV['AUTHENTICATION_PATH']
        (authentication_uri.nil? || authentication_path.nil?) ?
          @publisher = Publisher.new :
          @publisher = AuthenticatedPublisher.new(Publisher.new, authentication_uri, authentication_path)
      end

      def ping
        @ping ||= Ping.new
      end
    end
  end
end