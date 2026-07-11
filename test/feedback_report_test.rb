# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "open3"
require "uri"
require "cgi"

require_relative "../scripts/lib/feedback_report"

# FeedbackReportTest (intent 174): proves the engine's redaction, version
# fill, slug/collision naming, URL shape, and byte-cap behavior, plus one
# Open3 smoke test of the CLI. Hermetic: every case builds an isolated
# `plastic_home` under Dir.mktmpdir and a fixed `now`, so nothing touches the
# real ~/.plastic/feedback directory.
class FeedbackReportTest < Minitest::Test
  def setup
    @home = Dir.mktmpdir("feedback-report-test")
    @now = Time.utc(2026, 7, 11, 12, 0, 0)
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  def fr(**opts)
    FeedbackReport.new(plastic_home: @home, now: @now, **opts)
  end

  # --- redaction ---

  def test_redaction_strips_every_pattern_before_write
    secrets = [
      "ghp_" + ("a1B2c3D4e5F6g7H8i9J0" * 1),
      "sk-ant-" + ("a1B2c3D4e5F6g7H8i9J0" * 1),
      "AKIA" + ("A" * 16),
    ]
    body = <<~BODY
      What happened: hit an error with token #{secrets[0]}
      Also leaked #{secrets[1]} in a log line.
      AWS key #{secrets[2]} was printed too.
      password = hunter2secret
    BODY

    result = fr.compose(title: "leaked secrets", body: body)

    secrets.each do |secret|
      refute_includes result.body, secret, "composed body must not contain raw secret #{secret}"
    end
    refute_includes result.body, "hunter2secret", "composed body must not contain the raw password value"
    assert_includes result.body, "[REDACTED]"

    fr.persist(result)
    written = File.read(result.report_path)
    secrets.each do |secret|
      refute_includes written, secret, "written file must not contain raw secret #{secret}"
    end
    refute_includes written, "hunter2secret", "written file must not contain the raw password value"
  end

  def test_sk_ant_pattern_wins_over_shorter_sk_pattern
    engine = fr
    secret = "sk-ant-" + ("z9Y8x7W6v5U4t3S2r1Q0" * 1)
    redacted = engine.redact("key is #{secret} end")
    assert_equal "key is [REDACTED] end", redacted
  end

  # A secret pasted into the TITLE (not the body) must be redacted before it
  # reaches the URL's `title=` param or the report filename, exactly like a
  # secret in the body. Regression: compose() used to thread only `body`
  # through redact(), leaving `title` to flow raw into build_url/apply_cap
  # and slug_for/report_path.
  def test_title_secret_is_redacted_in_url_and_filename
    secret = "Bearer " + ("a1B2c3D4e5F6g7H8i9J0" * 1)
    title = "Error: #{secret} rejected"

    result = fr.compose(title: title, body: "harmless body, no secrets here")

    refute_includes result.url, "a1B2c3D4e5F6g7H8i9J0", "URL must not carry the raw title secret"
    assert_includes result.url, CGI.escape("[REDACTED]"), "URL title param should carry the redacted marker"
    refute_includes File.basename(result.report_path), "a1b2c3d4e5f6g7h8i9j0",
      "report filename slug must not carry the raw title secret"

    query = URI.parse(result.url).query
    params = Hash[URI.decode_www_form(query)]
    assert_equal "Error: [REDACTED] rejected", params["title"],
      "decoded title param should show the redacted title, not the raw secret"
  end

  # --- version fill ---

  def test_version_fill_present
    File.write(File.join(@home, "VERSION"), "1.4.2\n")
    result = fr.compose(title: "version present", body: "Running {{plastic_version}}.")
    assert_includes result.body, "Running 1.4.2."
    refute_includes result.body, "{{plastic_version}}"
  end

  def test_version_fill_absent_falls_back_to_unknown
    result = fr.compose(title: "version absent", body: "Running {{plastic_version}}.")
    assert_includes result.body, "Running unknown."
  end

  # --- slug + collision ---

  def test_report_path_slug_shape
    path = fr.report_path("Gate misfires on X")
    assert_equal "2026-07-11--gate-misfires-on-x.md", File.basename(path)
  end

  def test_report_path_collision_suffixing
    engine = fr
    first = engine.compose(title: "Gate misfires on X", body: "one")
    engine.persist(first)

    second = engine.compose(title: "Gate misfires on X", body: "two")
    engine.persist(second)

    third = engine.compose(title: "Gate misfires on X", body: "three")
    engine.persist(third)

    assert_equal "2026-07-11--gate-misfires-on-x.md", File.basename(first.report_path)
    assert_equal "2026-07-11--gate-misfires-on-x--2.md", File.basename(second.report_path)
    assert_equal "2026-07-11--gate-misfires-on-x--3.md", File.basename(third.report_path)
  end

  # --- url params ---

  def test_url_has_only_title_and_body_params_correctly_encoded
    title = "A quirk: weird & broken"
    body = "line one\nline two with spaces"
    result = fr.compose(title: title, body: body)

    assert result.url.start_with?("https://github.com/zalom/plastic/issues/new?title=")
    assert_includes result.url, "&body="
    refute_includes result.url, "template="
    refute_includes result.url, "labels="

    query = URI.parse(result.url).query
    params = Hash[URI.decode_www_form(query)]
    assert_equal title, params["title"]
    assert_equal result.body, params["body"]
  end

  # --- under cap ---

  def test_under_cap_short_body
    result = fr.compose(title: "short report", body: "Short body, no secrets, no cap issue.")
    refute result.truncated
    assert result.encoded_url_bytes <= 7500
    assert_nil result.page_break_note

    query = URI.parse(result.url).query
    params = Hash[URI.decode_www_form(query)]
    assert_equal "Short body, no secrets, no cap issue.", params["body"]
  end

  # --- over cap ---

  def test_over_cap_body_truncates_with_end_marker_and_keeps_full_file
    engine = fr
    big_body = "x" * 20_000
    result = engine.compose(title: "oversized report", body: big_body)

    assert result.truncated
    assert result.encoded_url_bytes <= 7500
    refute_nil result.page_break_note
    assert_includes result.page_break_note, result.report_path

    query = URI.parse(result.url).query
    params = Hash[URI.decode_www_form(query)]
    url_body = params["body"]
    assert url_body.end_with?(result.page_break_note),
      "page-one url body should end with the end-marker naming the local file"
    refute_includes url_body, "clipboard"
    refute_includes url_body, "paste into"

    engine.persist(result)
    written = File.read(result.report_path)
    assert_equal big_body, written, "the full uncapped body must land on disk"
    assert written.length > url_body.length, "the disk copy must be larger than the capped url body"
  end

  # --- CLI smoke ---

  def test_cli_smoke_via_open3
    cli = File.expand_path("../scripts/feedback-report", __dir__)
    fake_home = Dir.mktmpdir("feedback-report-cli-home")
    begin
      stdout, stderr, status = Open3.capture3(
        { "HOME" => fake_home },
        "ruby", cli, "--title", "manual smoke",
        stdin_data: "body {{plastic_version}}"
      )

      assert status.success?, "CLI should exit 0, stderr: #{stderr}"
      parsed = JSON.parse(stdout)
      %w[report_path url encoded_url_bytes truncated page_break_note].each do |key|
        assert parsed.key?(key), "CLI JSON missing key #{key}"
      end
      assert File.exist?(parsed["report_path"]), "CLI should have written the report file"
    ensure
      FileUtils.rm_rf(fake_home)
    end
  end
end
