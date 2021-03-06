require 'faraday'

module Firehose
  module Rack
    class AuthenticatedPublisher
      include Firehose::Rack::Helpers

      attr_reader :authentication_uri, :authentication_path

      def initialize(publisher, authentication_uri, authentication_path)
        @publisher = publisher
        @authentication_uri = authentication_uri
        @authentication_path = authentication_path
      end

      # Intercept incoming publishing (PUT) requests:
      #   - extract token from request
      #   - send HEAD request to club.bookmetender.com to verify authorization:
      #     - pass on to Publisher if recognized and authorized (received 200)
      #     - send unauthorized response otherwise (received 404)
      def call(env)
        authorized = false
        auth_header = env['HTTP_AUTHORIZATION']

        unless auth_header.nil? or (token = token_from(auth_header)).nil?
          begin
            req = env['parsed_request']
            model_name, model_id = model_from req.path
            unless model_name.nil? || model_id.nil?
              response = conn.head do |req|
                req.path = "#{authentication_path}/#{model_name}/#{model_id}/#{token}"
              end

              response.on_complete do
                case response.status
                when 200
                  authorized = true
                end
              end
            end
          rescue Faraday::ConnectionFailed => e
            Firehose.logger.error "Connection to authentication service #{authentication_uri} failed: #{e.message}."
          end
        end
        Firehose.logger.error "Refusing message from #{env['REMOTE_ADDR']}#{env['PATH_INFO']} (auth from header: #{auth_header}): NOT AUTHORIZED." unless authorized
        authorized ? publisher.call(env) : unauthorized
      end

      def authentication_service_healthy?
        healthy = false
        begin
          response = conn.head do |req|
            req.path = '/health/status'
          end

          response.on_complete do
            case response.status
            when 200
              healthy = true
            end
          end
        rescue Exception => e
          Firehose.logger.error "No connection to authentication service #{authentication_uri}: #{e.message}."
        end
        healthy
      end

      private
      def publisher
        @publisher
      end

      def unauthorized
        [401, {'Content-Type' => 'text/plain'}, ['Unauthorized']]
      end

      # data contains something like this: Token token='some auth token'
      def token_from(data)
        extract_from(data, /Token token='(.+)'/).first rescue nil
      end

      # extract model name and id from paths like "/guest_lists/23"
      # can also handle paths like "/events/23/entry_counters"
      def model_from(path)
        extract_from path, /\/(\w+)\/(\d+)/
      end

      # return array of captured matches
      def extract_from(data, pattern)
        matches = data.rstrip.scan pattern
        matches.first if matches.size == 1 && matches.first.size > 0
      end

      # Faraday connection to authentication server
      def conn
        @conn ||= Faraday.new(url: authentication_uri.to_s) do |builder|
          builder.adapter Faraday.default_adapter
        end
      end
    end
  end
end
