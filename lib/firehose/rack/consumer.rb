require 'json'

module Firehose
  module Rack
    # Handles a subscription request over HTTP or WebSockets depeding on its abilities and
    # binds that to the Firehose::Server::Subscription class, which is bound to a channel that
    # gets published to.
    class Consumer
      # Rack consumer transports
      autoload :HttpLongPoll, 'firehose/rack/consumer/http_long_poll'
      autoload :WebSocket,    'firehose/rack/consumer/web_socket'

      # Let the client configure the consumer on initialization.
      def initialize
        yield self if block_given?
      end

      def call(env)
        if allowed_origin?(env['HTTP_ORIGIN'])
          websocket_request?(env) ? websocket.call(env) : http_long_poll.call(env)
        else
          # send unauthorized
          Firehose.logger.error "Consumer request '#{env['REQUEST_URI']}' denied for origin '#{env['HTTP_ORIGIN']}'. Only allow from '#{ENV['ALLOW_ORIGIN']}'"
          [ 401, {}, [] ]
        end
      end

      # Memoized instance of web socket that can be configured from the rack app.
      def websocket
        @web_socket ||= WebSocket.new
      end

      # Memoized instance of http long poll handler that can be configured from the rack app.
      def http_long_poll
        @http_long_poll ||= HttpLongPoll.new
      end

      private
      # Determine if the incoming request is a websocket request.
      def websocket_request?(env)
        Firehose::Rack::Consumer::WebSocket.request?(env)
      end

      def allowed_origin?(origin)
        return true if ENV['ALLOW_ORIGIN'].nil?
        ENV['ALLOW_ORIGIN'].split(' ').include?(origin)
      end
    end
  end
end
