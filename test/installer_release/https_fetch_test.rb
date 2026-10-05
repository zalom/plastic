# frozen_string_literal: true

require "net/http"
require_relative "release_helper"

class InstallerReleaseHttpsFetchTest < Minitest::Test
  include ReleaseHelper

  # Answers each URL from a table, the way Net::HTTP.get_response would.
  class FakeHttp
    attr_reader :asked, :headers

    def initialize(answers)
      @answers = answers
      @asked = []
      @headers = []
    end

    def get_response(uri, headers)
      @asked << uri.to_s
      @headers << headers
      @answers.fetch(uri.to_s)
    end
  end

  def test_reads_a_url_over_https
    http = FakeHttp.new("https://example.test/a" => ok("body"))

    assert_equal "body", fetch(http).read("https://example.test/a")
  end

  def test_follows_a_redirect
    http = FakeHttp.new("https://example.test/a" => redirect("https://cdn.example.test/b"), "https://cdn.example.test/b" => ok("moved"))

    assert_equal "moved", fetch(http).read("https://example.test/a")
    assert_equal %w[https://example.test/a https://cdn.example.test/b], http.asked
  end

  def test_refuses_a_url_that_is_not_https
    error = assert_raises(InstallerRelease::FetchError) { fetch(FakeHttp.new({})).read("http://example.test/a") }
    assert_equal "refusing http://example.test/a: not HTTPS", error.message
  end

  def test_refuses_a_redirect_away_from_https
    http = FakeHttp.new("https://example.test/a" => redirect("http://example.test/b"))

    assert_raises(InstallerRelease::FetchError) { fetch(http).read("https://example.test/a") }
  end

  def test_stops_after_too_many_redirects
    http = FakeHttp.new("https://example.test/a" => redirect("https://example.test/a"))

    error = assert_raises(InstallerRelease::FetchError) { fetch(http).read("https://example.test/a") }
    assert_equal "too many redirects from https://example.test/a", error.message
  end

  def test_names_a_failed_answer
    http = FakeHttp.new("https://example.test/a" => Net::HTTPNotFound.new("1.1", "404", "Not Found"))

    error = assert_raises(InstallerRelease::FetchError) { fetch(http).read("https://example.test/a") }
    assert_equal "https://example.test/a answered 404", error.message
  end

  def test_downloads_into_a_file
    path = File.join(@root, "asset")
    fetch(FakeHttp.new("https://example.test/a" => ok("bytes"))).download("https://example.test/a", path)

    assert_equal "bytes", File.binread(path)
  end

  def test_sends_the_headers_to_the_first_address_only
    http = FakeHttp.new("https://example.test/a" => redirect("https://cdn.example.test/b"), "https://cdn.example.test/b" => ok("moved"))
    fetch(http).download("https://example.test/a", File.join(@root, "asset"), "Authorization" => "Bearer QQ==")

    assert_equal [{ "Authorization" => "Bearer QQ==" }, {}], http.headers
  end

  private

  def fetch(http) = InstallerRelease::HttpsFetch.new(http: http)

  def ok(body)
    response = Net::HTTPOK.new("1.1", "200", "OK")
    response.define_singleton_method(:body) { body }
    response
  end

  def redirect(location)
    response = Net::HTTPFound.new("1.1", "302", "Found")
    response["location"] = location
    response
  end
end
