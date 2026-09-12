require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"

# Coverage for the insight-append CLI's --rule flag (intent 341, G8, C37): a
# `rule:` tag marks an Insights entry doctor can later check against the
# conventions chapters. The base append path (no --rule) is already covered
# by test/insights_test.rb; this file covers only the CLI's own flag.
class InsightAppendRuleFlagTest < Minitest::Test
  CLI = File.expand_path("../scripts/insight-append", __dir__)

  def setup
    @dir = Dir.mktmpdir("insight-append-rule-test")
    @intent_dir = File.join(@dir, "34--sample-intent")
    FileUtils.mkdir_p(@intent_dir)
    File.write(intent_file, <<~MD)
      ---
      id: "34"
      intent: "Sample intent"
      ---

      ## Insights
    MD
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def intent_file
    File.join(@intent_dir, "34--sample-intent.md")
  end

  def run_cli(*args)
    Open3.capture3("ruby", CLI, *args)
  end

  def test_rule_flag_tags_the_entry
    out, err, status = run_cli(@intent_dir, "Never eval a prompt string", "--stage", "Exec",
                                "--author", "test", "--rule")
    assert status.success?, err
    assert_includes out, "rule:"

    last_line = File.read(intent_file).lines.last.chomp
    assert_match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z · Exec · test — rule: Never eval a prompt string\z/,
                 last_line)
  end

  def test_without_rule_flag_no_tag_is_added
    _out, err, status = run_cli(@intent_dir, "An ordinary observation", "--stage", "Exec", "--author", "test")
    assert status.success?, err

    last_line = File.read(intent_file).lines.last.chomp
    refute_match(/— rule:/, last_line)
    assert_match(/— An ordinary observation\z/, last_line)
  end
end
