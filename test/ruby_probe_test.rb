# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"

require_relative "../scripts/lib/ruby_probe"

# Hermetic proof that the RUBYOPT clearing mechanism actually works (intent 235, AC5).
# No real process is spawned, no ENV is read or written, no eval. The capture seam is
# injected as a lambda.
#
# The fake below mirrors the behavior verified on a real machine: with RUBYOPT=--yjit
# inherited, /usr/bin/ruby 2.6.10 dies with "invalid option --yjit", while the same
# call with {"RUBYOPT" => nil} as the leading env hash succeeds. The control test
# proves the fake is genuinely sensitive, so the passing test is not vacuous.
class RubyProbeTest < Minitest::Test
  INHERITED_RUBYOPT = "--yjit"

  # A fake interpreter that dies on --yjit, exactly like Ruby 2.6 does.
  # Records every call so a test can assert what reached the child.
  def sensitive_capture(calls)
    lambda do |env, command, *args|
      calls << { env: env, command: command, args: args }
      effective = env.key?("RUBYOPT") ? env["RUBYOPT"].to_s : INHERITED_RUBYOPT
      next ["", false] if effective.include?("--yjit")

      ["2.6.10\n/usr/bin/ruby\n", true]
    end
  end

  def test_resolve_passes_a_clearing_env_hash_to_the_child_call
    calls = []
    RubyProbe.resolve(capture: sensitive_capture(calls))

    assert_equal 1, calls.size
    env = calls.first[:env]
    assert env.key?("RUBYOPT"), "the env hash must carry the RUBYOPT key, a merge clears nothing without it"
    assert_nil env["RUBYOPT"]
  end

  def test_clearing_lets_a_rubyopt_sensitive_interpreter_answer
    result = RubyProbe.resolve(capture: sensitive_capture([]))

    assert result[:found]
    assert_equal "2.6.10", result[:version]
    assert_equal "/usr/bin/ruby", result[:path]
  end

  # Control: without the clearing hash the same fake fails, so the test above proves
  # something. If this ever passes, the fake stopped being RUBYOPT sensitive.
  def test_the_same_call_without_clearing_fails_on_the_same_fake
    _out, ok = sensitive_capture([]).call({}, "ruby", "-v")

    refute ok
  end

  def test_resolve_spawns_the_bare_name_so_the_os_resolves_path
    calls = []
    RubyProbe.resolve(capture: sensitive_capture(calls))

    assert_equal "ruby", calls.first[:command]
  end

  def test_a_failing_capture_reports_not_found
    result = RubyProbe.resolve(capture: ->(*) { ["", false] })

    refute result[:found]
    assert_nil result[:version]
    assert_nil result[:path]
  end

  def test_unparseable_output_reports_not_found
    result = RubyProbe.resolve(capture: ->(*) { ["", true] })

    refute result[:found]
  end

  def test_a_raising_capture_reports_not_found_instead_of_crashing
    result = RubyProbe.resolve(capture: ->(*) { raise Errno::ENOENT, "ruby" })

    refute result[:found]
  end
end
