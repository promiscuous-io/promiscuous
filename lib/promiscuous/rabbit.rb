require 'net/http'
require 'uri'

module Promiscuous::Rabbit
  class Policy
    def self.set(queue, attributes)
      uri = uri_for(queue)

      request = Net::HTTP::Put.new(uri.request_uri, http_headers)
      request.basic_auth(uri.user, uri.password) if uri.user
      request.body = MultiJson.dump(attributes)

      http = Net::HTTP.new(uri.host, uri.port)
      response = http.request(request)

      raise "Unable to connect to Rabbit #{response.body}" unless response.is_a?(Net::HTTPSuccess)
    end

    def self.delete(queue)
      uri = uri_for(queue)

      request = Net::HTTP::Delete.new(uri.request_uri, http_headers)
      request.basic_auth(uri.user, uri.password) if uri.user

      http = Net::HTTP.new(uri.host, uri.port)
      response = http.request(request)

      raise "Unable to connect to Rabbit #{response.body}" unless response.is_a?(Net::HTTPSuccess) || response.is_a?(Net::HTTPNotFound)
    end

    private

    def self.uri_for(queue)
      URI.parse("#{Promiscuous::Config.rabbit_mgmt_url}/api/policies/%2f/#{queue}-retry")
    end

    def self.http_headers
      {'Content-Type' =>'application/json'}
    end
  end
end
