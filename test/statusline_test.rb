# encoding: UTF-8
require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"

# Hermetic tests for hooks/statusline (intent 279: the line reports what this
# session is spending, not which intent it is on). The repo script runs as a
# subprocess with crafted stdin JSON and an isolated HOME (Dir.mktmpdir), so nothing
# touches the real store or /tmp. Pure-bash dependency injection through the
# environment: no monkeypatching, no eval.
class StatuslineTest < Minitest::Test
  STATUSLINE = File.expand_path("../hooks/statusline", __dir__)
  YELLOW = "\e[33m"
  RED = "\e[38;2;231;76;60m"

  def setup
    @home = Dir.mktmpdir("statusline-home")
    @cwd = File.join(@home, "apps", "plastic")
    FileUtils.mkdir_p(@cwd)
    FileUtils.mkdir_p(File.join(@home, ".plastic"))
    # A VERSION file so the version segment renders (keeps the line realistic).
    File.write(File.join(@home, ".plastic", "VERSION"), "1.2.3\n")
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  # --- helpers ---------------------------------------------------------------

  def render_raw(stdin_json)
    out = nil
    IO.popen({ "HOME" => @home },
             [STATUSLINE], "r+") do |io|
      io.write(stdin_json)
      io.close_write
      out = io.read
    end
    out
  end

  def render(stdin_json)
    render_raw(stdin_json).gsub(/\e\[[0-9;]*m/, "") # strip ANSI
  end

  # Build the statusline stdin payload. A section passed as nil is omitted, which
  # is how an API-key session (no rate_limits) and a costless session arrive.
  def stdin_json(session_id: nil, cwd: @cwd, context_window: nil,
                 rate_limits: nil, cost: nil, pretty: false)
    payload = {
      "model" => { "display_name" => "Opus" },
      "workspace" => { "current_dir" => cwd },
      "cwd" => cwd,
    }
    payload["session_id"] = session_id if session_id
    payload["context_window"] = context_window if context_window
    payload["rate_limits"] = rate_limits if rate_limits
    payload["cost"] = cost if cost
    pretty ? JSON.pretty_generate(payload) : JSON.generate(payload)
  end

  def ctx(used_percentage: 42, size: 200_000, current_usage: nil)
    {
      "context_window_size" => size,
      "used_percentage" => used_percentage,
      "current_usage" => current_usage,
    }
  end

  # 60000 + 4000 + 20000 = 84000 input-side tokens, 42% of a 200k window.
  def usage(input: 60_000, cache_creation: 4_000, cache_read: 20_000, output: 1_200)
    {
      "input_tokens" => input,
      "output_tokens" => output,
      "cache_creation_input_tokens" => cache_creation,
      "cache_read_input_tokens" => cache_read,
    }
  end

  # --- cases -----------------------------------------------------------------

  def test_renders_model_version_and_path
    out = render(stdin_json)
    assert_includes out, "Opus"
    assert_includes out, "Plastic 1.2.3"
    assert_includes out, "~/apps/plastic"
  end

  def test_context_window_from_current_usage
    out = render(stdin_json(context_window: ctx(current_usage: usage)))
    assert_includes out, "ctx 42%"
    assert_includes out, "(84k/200k)"
  end

  def test_context_window_reads_pretty_printed_json
    # The extractor must not depend on layout: context_window holds a nested
    # current_usage object, which a sed line range would close too early.
    flat = render(stdin_json(context_window: ctx(current_usage: usage)))
    pretty = render(stdin_json(context_window: ctx(current_usage: usage), pretty: true))
    assert_includes pretty, "ctx 42%"
    assert_includes pretty, "(84k/200k)"
    assert_equal flat, pretty
  end

  def test_context_window_derives_percentage_from_usage
    out = render(stdin_json(context_window: ctx(used_percentage: nil, current_usage: usage)))
    assert_includes out, "ctx 42%"
    assert_includes out, "(84k/200k)"
  end

  def test_context_window_omitted_when_percentage_and_usage_are_null
    out = render(stdin_json(context_window: ctx(used_percentage: nil, current_usage: nil)))
    refute_includes out, "ctx"
  end

  def test_context_window_size_at_one_million_renders_with_m
    # Sizes and used counts below 1M keep "k"; at or above 1M they switch to "M".
    out = render(stdin_json(context_window: ctx(
      used_percentage: 42, size: 1_000_000,
      current_usage: usage(input: 360_000, cache_creation: 40_000, cache_read: 20_000)
    )))
    assert_includes out, "ctx 42%"
    assert_includes out, "(420k/1M)"
  end

  def test_context_omitted_for_exponent_notation
    # Some JSON writers emit scientific notation for tiny fractions; the awk
    # walker must not misread "8e-7" as a huge or wrong percentage, so it
    # drops the field and the segment renders as absent.
    raw = %({"model":{"display_name":"Opus"},"cwd":"#{@cwd}","context_window":{"used_percentage":8e-7}})
    refute_includes render(raw), "ctx"
  end

  def test_meters_render_with_threshold_colors
    quiet = render_raw(stdin_json(rate_limits: { "five_hour" => { "used_percentage" => 42 } }))
    assert_includes quiet.gsub(/\e\[[0-9;]*m/, ""), "5h 42%"
    refute_includes quiet, "#{YELLOW}5h"
    refute_includes quiet, "#{RED}5h"

    warn = render_raw(stdin_json(rate_limits: { "five_hour" => { "used_percentage" => 70 } }))
    assert_includes warn, "#{YELLOW}5h 70%"

    crit = render_raw(stdin_json(rate_limits: { "five_hour" => { "used_percentage" => 92 } }))
    assert_includes crit, "#{RED}5h 92%"
  end

  def test_meters_render_decimal_values_from_documented_payload
    out = render(stdin_json(rate_limits: {
      "five_hour" => { "used_percentage" => 23.5 },
      "seven_day" => { "used_percentage" => 41.2 },
    }))
    assert_includes out, "5h 23%"
    assert_includes out, "7d 41%"
  end

  def test_meter_color_boundaries
    # D4: yellow at 70 and above, red at 90 and above; truncation (not rounding)
    # decides which side of a decimal boundary a meter lands on.
    red = render_raw(stdin_json(rate_limits: { "five_hour" => { "used_percentage" => 90 } }))
    assert_includes red, "#{RED}5h 90%"

    yellow_high = render_raw(stdin_json(rate_limits: { "five_hour" => { "used_percentage" => 89.6 } }))
    assert_includes yellow_high, "#{YELLOW}5h 89%"
    refute_includes yellow_high, "#{RED}5h"

    yellow_low = render_raw(stdin_json(rate_limits: { "five_hour" => { "used_percentage" => 70 } }))
    assert_includes yellow_low, "#{YELLOW}5h 70%"

    default = render_raw(stdin_json(rate_limits: { "five_hour" => { "used_percentage" => 69.9 } }))
    assert_includes default.gsub(/\e\[[0-9;]*m/, ""), "5h 69%"
    refute_includes default, "#{YELLOW}5h"
    refute_includes default, "#{RED}5h"
  end

  def test_meters_absent_without_rate_limits
    out = render(stdin_json)
    refute_includes out, "5h"
    refute_includes out, "7d"
  end

  def test_seven_day_renders_without_five_hour
    out = render(stdin_json(rate_limits: { "seven_day" => { "used_percentage" => 13 } }))
    assert_includes out, "7d 13%"
    refute_includes out, "5h"
  end

  def test_cost_hidden_when_zero_or_absent
    refute_includes render(stdin_json(cost: { "total_cost_usd" => 0 })), "$"
    refute_includes render(stdin_json), "$"
  end

  def test_cost_renders_two_decimals
    out = render(stdin_json(cost: { "total_cost_usd" => 1.2345 }))
    assert_includes out, "$1.23"
  end

  def test_cost_hidden_for_exponent_notation
    # A JSON writer can emit "1.2e-6" for a tiny cost; the awk walker must not
    # misread that as a huge dollar figure, so it drops the field entirely.
    raw = %({"model":{"display_name":"Opus"},"cwd":"#{@cwd}","cost":{"total_cost_usd":1.2e-6}})
    refute_includes render(raw), "$"
  end

  def test_no_claudish_segment
    code = File.read(STATUSLINE)
    refute_includes code, "claudish", "the claudish segment was removed (owner ruling 2026-09-02)"
    refute_includes render(stdin_json(session_id: "sess-A")), "claudish"
  end

  def test_no_intent_resolution_remains
    code = File.read(STATUSLINE)
    ["projects.yml", "INDEX.md", "savepoint", "PLASTIC_TMP", "plastic-${SID}"].each do |token|
      refute_includes code, token,
                      "statusline must not resolve an active intent any more (intent 279)"
    end
  end

  def test_header_declares_hook_version_4
    header = File.read(STATUSLINE).lines.first(6).join
    assert_includes header, "plastic-hook-version: 4.0.0"
  end

  def test_no_ruby_or_jq_invoked
    # Strip comments; assert no ruby/jq token survives in executable lines.
    body = File.read(STATUSLINE)
    code = body.each_line.reject { |l| l.strip.start_with?("#") }.join
    refute_match(/\b(ruby|jq)\b/, code,
                 "statusline must not invoke ruby or jq (intent 59 constraint)")
  end
end
