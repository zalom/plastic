# frozen_string_literal: true

require "net/http"
require "uri"

module InstallerRelease
  class FetchError < StandardError; end

  # Reads and downloads over HTTPS only, following a few redirects.
  class HttpsFetch
    REDIRECTS = 5

    def initialize(http: Net::HTTP)
      @http = http
    end

    def read(url) = response(url).body

    def download(url, path)
      File.binwrite(path, read(url))
      path
    end

    private

    attr_reader :http

    def response(url, hops = REDIRECTS)
      answer = http.get_response(https(url))
      return answer if answer.is_a?(Net::HTTPSuccess)

      follow(url, answer, hops)
    end

    def https(url)
      uri = URI(url)
      raise FetchError, "refusing #{url}: not HTTPS" unless uri.scheme == "https"

      uri
    end

    def follow(url, answer, hops)
      raise FetchError, "#{url} answered #{answer.code}" unless answer.is_a?(Net::HTTPRedirection)
      raise FetchError, "too many redirects from #{url}" if hops.zero?

      response(answer["location"], hops - 1)
    end
  end
end
