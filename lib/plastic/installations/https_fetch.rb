# frozen_string_literal: true

require "net/http"
require "openssl"
require "uri"
require_relative "../errors"

module Plastic
  module Installations
    # The release source could not be read. A failure, so the person gets its
    # message with no class name, and the call exits 1.
    class FetchError < Failed; end

    # Reads and downloads over HTTPS only, following a few redirects. The
    # headers go to the first address only, never to a redirect target.
    class HttpsFetch
      REDIRECTS = 5
      # What a person meets when the host cannot be reached: connection refused,
      # reset or unreachable (SystemCallError), a name that does not resolve
      # (SocketError), a timeout, a closed stream and a TLS failure.
      UNREACHABLE = [SystemCallError, SocketError, Timeout::Error, EOFError, OpenSSL::SSL::SSLError].freeze

      def initialize(http: Net::HTTP)
        @http = http
      end

      def read(url) = response(url).body

      def download(url, path, headers = {})
        File.binwrite(path, response(url, headers).body)
        path
      end

      private

      attr_reader :http

      def response(url, headers = {}, hops = REDIRECTS)
        answer = naming(url) { http.get_response(https(url), headers) }
        return answer if answer.is_a?(Net::HTTPSuccess)

        follow(url, answer, hops)
      end

      def naming(url)
        yield
      rescue *UNREACHABLE => error
        raise FetchError, "cannot reach #{url}: #{error.message}"
      end

      def https(url)
        uri = URI(url)
        raise FetchError, "refusing #{url}: not HTTPS" unless uri.scheme == "https"

        uri
      end

      def follow(url, answer, hops)
        raise FetchError, "#{url} answered #{answer.code}" unless answer.is_a?(Net::HTTPRedirection)
        raise FetchError, "too many redirects from #{url}" if hops.zero?

        response(answer["location"], {}, hops - 1)
      end
    end
  end
end
