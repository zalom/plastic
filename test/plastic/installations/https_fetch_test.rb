# frozen_string_literal: true

require_relative "../../test_helper"
require "net/http"
require "openssl"
require "openssl"
require "plastic/installations/https_fetch"

class HttpsFetchTest < Plastic::TestCase
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

  # A success answer that carries its body, the way a read answer does.
  class Ok < Net::HTTPOK
    attr_reader :body

    def initialize(body)
      super("1.1", "200", "OK")
      @body = body
    end
  end

  def test_a_url_over_https_is_read
    http = FakeHttp.new("https://example.test/a" => ok("body"))

    assert_equal "body", fetch(http).read("https://example.test/a")
  end

  def test_a_redirect_is_followed_to_its_target
    http = FakeHttp.new("https://example.test/a" => redirect("https://cdn.example.test/b"), "https://cdn.example.test/b" => ok("moved"))

    assert_equal "moved", fetch(http).read("https://example.test/a")
    assert_equal %w[https://example.test/a https://cdn.example.test/b], http.asked
  end

  def test_refuses_a_url_that_is_not_https
    error = assert_raises(Plastic::Installations::FetchError) { fetch(FakeHttp.new({})).read("http://example.test/a") }
    assert_equal "refusing http://example.test/a: not HTTPS", error.message
  end

  def test_refuses_a_redirect_away_from_https
    http = FakeHttp.new("https://example.test/a" => redirect("http://example.test/b"))

    assert_raises(Plastic::Installations::FetchError) { fetch(http).read("https://example.test/a") }
  end

  def test_stops_after_too_many_redirects
    http = FakeHttp.new("https://example.test/a" => redirect("https://example.test/a"))

    error = assert_raises(Plastic::Installations::FetchError) { fetch(http).read("https://example.test/a") }
    assert_equal "too many redirects from https://example.test/a", error.message
  end

  def test_names_a_failed_answer
    http = FakeHttp.new("https://example.test/a" => Net::HTTPNotFound.new("1.1", "404", "Not Found"))

    error = assert_raises(Plastic::Installations::FetchError) { fetch(http).read("https://example.test/a") }
    assert_equal "https://example.test/a answered 404", error.message
  end

  def test_downloads_into_a_file
    path = File.join(@home, "asset")
    fetch(FakeHttp.new("https://example.test/a" => ok("bytes"))).download("https://example.test/a", path)

    assert_equal "bytes", File.binread(path)
  end

  def test_sends_the_headers_to_the_first_address_only
    http = FakeHttp.new("https://example.test/a" => redirect("https://cdn.example.test/b"), "https://cdn.example.test/b" => ok("moved"))
    fetch(http).download("https://example.test/a", File.join(@home, "asset"), "Authorization" => "Bearer QQ==")

    assert_equal [{ "Authorization" => "Bearer QQ==" }, {}], http.headers
  end

  # Raises what Net::HTTP raises when the host cannot be reached.
  class Unreachable
    def initialize(error) = @error = error

    def get_response(_uri, _headers) = raise(@error)
  end

  NETWORK_ERRORS = {
    "connection refused" => Errno::ECONNREFUSED.new("connect(2) for example.test port 443"),
    "name not resolved" => SocketError.new("getaddrinfo: nodename nor servname provided"),
    "timeout" => Net::OpenTimeout.new("execution expired"),
    "TLS failure" => OpenSSL::SSL::SSLError.new("certificate verify failed"),
    "connection reset" => Errno::ECONNRESET.new
  }.freeze

  def test_a_network_error_is_a_plain_message_that_names_the_url
    NETWORK_ERRORS.each do |label, cause|
      error = assert_raises(Plastic::Installations::FetchError, label) { fetch(Unreachable.new(cause)).read("https://example.test/a") }

      assert_match(%r{\Acannot reach https://example.test/a: }, error.message, label)
      refute_match(/Errno|SocketError|Net::|OpenSSL/, error.message, label)
    end
  end

  def test_a_network_error_on_a_download_names_the_url_too
    error = assert_raises(Plastic::Installations::FetchError) do
      fetch(Unreachable.new(Errno::ECONNREFUSED.new)).download("https://example.test/f", File.join(@home, "f"))
    end

    assert_match(%r{\Acannot reach https://example.test/f: }, error.message)
  end

  def test_a_fetch_error_is_a_failure_so_it_exits_1_without_its_class_name
    assert_equal Plastic::Failed, Plastic::Installations::FetchError.superclass
  end

  def test_an_error_that_is_not_a_network_error_is_not_rescued
    assert_raises(NoMethodError) { fetch(Unreachable.new(NoMethodError.new("bug"))).read("https://example.test/a") }
  end

  # Raises what Net::HTTP raises when the host cannot be reached.
  class Unreachable
    def initialize(error) = @error = error

    def get_response(_uri, _headers) = raise(@error)
  end

  NETWORK_ERRORS = {
    "connection refused" => Errno::ECONNREFUSED.new("connect(2) for \"example.test\" port 443"),
    "name not resolved" => SocketError.new("getaddrinfo: nodename nor servname provided"),
    "timeout" => Net::OpenTimeout.new("execution expired"),
    "TLS failure" => OpenSSL::SSL::SSLError.new("certificate verify failed"),
    "connection reset" => Errno::ECONNRESET.new
  }.freeze

  def test_a_network_error_is_a_plain_message_that_names_the_url
    NETWORK_ERRORS.each do |label, cause|
      error = assert_raises(Plastic::Installations::FetchError, label) { fetch(Unreachable.new(cause)).read("https://example.test/a") }

      assert_match(%r{\Acannot reach https://example.test/a: }, error.message, label)
      refute_match(/Errno|SocketError|Net::|OpenSSL/, error.message, label)
    end
  end

  def test_a_network_error_on_a_download_names_the_url_too
    error = assert_raises(Plastic::Installations::FetchError) do
      fetch(Unreachable.new(Errno::ECONNREFUSED.new)).download("https://example.test/f", File.join(@home, "f"))
    end

    assert_match(%r{\Acannot reach https://example.test/f: }, error.message)
  end

  def test_a_fetch_error_is_a_failure_so_it_exits_1_without_its_class_name
    assert_equal Plastic::Failed, Plastic::Installations::FetchError.superclass
  end

  def test_an_error_that_is_not_a_network_error_is_not_rescued
    assert_raises(NoMethodError) { fetch(Unreachable.new(NoMethodError.new("bug"))).read("https://example.test/a") }
  end

  private

  def fetch(http) = Plastic::Installations::HttpsFetch.new(http: http)

  def ok(body) = Ok.new(body)

  def redirect(location)
    response = Net::HTTPFound.new("1.1", "302", "Found")
    response["location"] = location
    response
  end
end
