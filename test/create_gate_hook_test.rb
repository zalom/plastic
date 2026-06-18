# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"

# ACTION_5 (intent 60b): drive the real scripts/hook-create-gate as a subprocess
# with a JSON PreToolUse payload on stdin. The gate validates the PROPOSED content
# of a Write to an intent file, independent of any bridge or CLAUDE_SESSION_ID.
class CreateGateHookTest < Minitest::Test
  SCRIPT = File.expand_path("../scripts/hook-create-gate", __dir__)
  NEW_INTENT = File.expand_path("../scripts/new-intent", __dir__)
  TEMPLATES = File.expand_path("../templates", __dir__)

  def setup
    @root = Dir.mktmpdir("create-gate")
    @store = File.join(@root, "store")
    FileUtils.mkdir_p(@store)
    # Born-complete fixture: exactly what new-intent produces.
    out = IO.popen([RbConfig.ruby, NEW_INTENT, "--templates", TEMPLATES,
                    "--store", @store, "--intent", "Demo", "--slug", "demo"],
                   err: [:child, :out], &:read)
    @intent_dir = out.strip
    raise "new-intent failed: #{out}" unless $?.success?
    @intent_file = File.join(@intent_dir, "#{File.basename(@intent_dir)}.md")
    @born_complete = File.read(@intent_file)
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  # Run the gate with no bridge env at all (proves bridge-independence).
  def run_gate(payload, env: {})
    base = { "CLAUDE_SESSION_ID" => nil, "PLASTIC_TMP" => nil }
    full = base.merge(env)
    out = IO.popen(full, [RbConfig.ruby, SCRIPT], "r+", err: [:child, :out]) do |io|
      io.write(JSON.generate(payload))
      io.close_write
      io.read
    end
    [out, $?.exitstatus]
  end

  def write_payload(path, content)
    { "tool_input" => { "file_path" => path, "content" => content } }
  end

  def test_born_complete_intent_passes
    out, status = run_gate(write_payload(@intent_file, @born_complete))
    assert_equal 0, status, "born-complete new-intent output must pass: #{out}"
  end

  def test_incomplete_frontmatter_blocked
    bad = @born_complete.sub(/^chain:.*\n/, "")
    out, status = run_gate(write_payload(@intent_file, bad))
    assert_equal 2, status, "missing chain must block"
    assert_includes out, "PLASTIC CREATE GATE"
    assert_includes out, "chain"
  end

  def test_unknown_section_blocked
    bad = @born_complete + "\n## Bogus\nnope\n"
    out, status = run_gate(write_payload(@intent_file, bad))
    assert_equal 2, status, "unknown section must block"
    assert_includes out, "unknown section: ## Bogus"
  end

  def test_missing_links_section_blocked
    bad = @born_complete.sub(/## Links.*\z/m, "")
    out, status = run_gate(write_payload(@intent_file, bad))
    assert_equal 2, status, "missing ## Links must block"
    assert_includes out, "missing required section: ## Links"
  end

  def test_enforces_with_no_bridge
    # CLAUDE_SESSION_ID unset (default in run_gate) and PLASTIC_TMP empty:
    # the gate still blocks bad and passes good.
    _bad_out, bad_status = run_gate(write_payload(@intent_file, @born_complete.sub(/^chain:.*\n/, "")))
    assert_equal 2, bad_status
    _good_out, good_status = run_gate(write_payload(@intent_file, @born_complete))
    assert_equal 0, good_status
  end

  def test_non_intent_path_allowed
    spec_path = File.join(@intent_dir, "spec.md")
    out, status = run_gate(write_payload(spec_path, "<!-- plastic:placeholder -->\nanything\n"))
    assert_equal 0, status, "sibling lifecycle file must not be gated: #{out}"

    random = File.join(@store, "notes.md")
    _out2, status2 = run_gate(write_payload(random, "whatever"))
    assert_equal 0, status2, "non-intent store file must not be gated"
  end

  def test_missing_content_is_fail_safe_block
    payload = { "tool_input" => { "file_path" => @intent_file } }
    out, status = run_gate(payload)
    assert_equal 2, status, "missing content must fail safe (block)"
    assert_includes out, "cannot read proposed content"
  end

  def test_unparseable_payload_allowed
    out = IO.popen({ "CLAUDE_SESSION_ID" => nil }, [RbConfig.ruby, SCRIPT], "r+", err: [:child, :out]) do |io|
      io.write("not json at all")
      io.close_write
      io.read
    end
    assert_equal 0, $?.exitstatus, "unparseable payload must exit 0: #{out}"
  end
end
