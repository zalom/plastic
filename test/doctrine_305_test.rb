# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"

# The docs describe the 2.0 model: two modes plus auto, the record hook, the day
# ledger and the lock.
class Doctrine305Test < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  ADAPTERS = File.join(ROOT, "docs", "reference", "harness-adapters.md")
  GUIDES = File.join(ROOT, "docs", "guides")
  LEDGERS_GUIDE = File.join(GUIDES, "reading-the-ledgers.md")

  def test_adapters_doc_names_the_record_hook_and_the_shell_write_caveat
    body = File.read(ADAPTERS).gsub(/\s+/, " ")

    ["`record`", "three kernel hooks and the update check through `settings.json`", "does not include `Bash`"]
      .each { |phrase| assert_includes body, phrase }
  end

  def test_the_ledgers_guide_names_the_savepoint_the_day_ledger_and_the_lock
    body = File.read(LEDGERS_GUIDE)

    ["savepoint.md", ".sessions/<YYYYMMDD>/", "`heartbeat`", "delivery.lock"].each { |term| assert_includes body, term }
  end

  def test_guides_index_lists_the_ledgers_guide
    assert_includes File.read(File.join(GUIDES, "index.md")), "(reading-the-ledgers.md)"
  end

  def test_pick_your_mode_describes_direct_thinking_and_auto
    body = File.read(File.join(GUIDES, "pick-your-mode.md"))

    ["## Direct", "## Thinking", "## Auto"].each { |heading| assert_includes body, heading }
  end

  def test_tutorial_track_2_walks_the_record
    assert_includes File.read(File.join(ROOT, "docs", "help", "track-2-auto.md")), "### 3. Walking the record"
  end
end
