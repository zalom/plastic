# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require_relative "varar/support/public_command"

# Intent 385: a Future intent closes through the same lifecycle path as an
# Active one, and `plastic intent end --dry-run` resolves the INDEX entry the
# way the real close does, before anything is written. Driven through the
# repository's own bin/plastic against a disposable PLASTIC_HOME. Owner
# ruling 2026-09-24 (intent 390): Plastic runs no version control command,
# so the global store here is a PLAIN directory, never a real git
# repository - the close's own "commit" is a printed instruction, checked
# against stdout and the files it names, never a real git log.
class EndIntentFutureCloseTest < Minitest::Test
  ABANDON = ["intent", "end", "1", "--abandoned", "--summary", "superseded by a wider intent",
    "--note", "successor: intent 2"].freeze

  def setup
    @home = Dir.mktmpdir("end-future-close")
    @command = PublicCommand.new(@home)
    @global = @command.global
    @index = File.join(@global, "INDEX.md")
    File.write(@index, "# Index\n\n## Active\n\n## Future\n\n## Completed\n\n## Abandoned\n")
    plastic("intent", "new", "later work", "--slug", "later")
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  def plastic(*args)
    @command.run(*args)
  end

  # Moves the intent's INDEX line into ## Future (or drops it).
  def file_under(section)
    text = File.read(@index)
    line = text[/^- \[1 .*\n/]
    text = text.sub(line, "")
    text = text.sub("## #{section}\n", "## #{section}\n#{line}") if section
    File.write(@index, text)
  end

  def section_of(id)
    heading = nil
    File.foreach(@index) do |line|
      heading = line.delete_prefix("## ").strip if line.start_with?("## ")
      return heading if line.start_with?("- [#{id} ")
    end
    nil
  end

  def snapshot
    Dir.glob("#{@global}/**/*", File::FNM_DOTMATCH).reject { |f| f.include?("/.git/") }
      .select { |f| File.file?(f) }.sort.to_h { |f| [f, File.read(f)] }
  end

  def intent_dir
    File.join(@global, "store", "1--later")
  end

  def test_future_abandon_preview_names_future_and_writes_nothing
    file_under("Future")
    before = snapshot

    status, out, err = plastic(*ABANDON, "--dry-run", "--json")

    assert_equal 0, status, err
    assert_includes JSON.parse(out).dig("result", "output").join, "would move INDEX.md entry from ## Future to ## Abandoned"
    assert_equal before, snapshot
  end

  def test_future_abandon_moves_the_entry_to_abandoned_with_the_note
    file_under("Future")

    status, _out, err = plastic(*ABANDON)

    assert_equal 0, status, err
    assert_equal "Abandoned", section_of("1")
    assert_match(/^- \[1 \u2014 later work\]\(store\/1--later\/1--later\.md\) \u2014 \d{4}-\d{2}-\d{2} successor: intent 2$/,
      File.read(@index))
  end

  def test_future_abandon_writes_the_terminal_record
    file_under("Future")

    _status, out, = plastic(*ABANDON)

    assert_includes out, "next: plastic status\nbecause: the intent is now closed"
    assert_includes File.read(File.join(intent_dir, "savepoint.md")), "Done  abandoned"
    assert_includes File.read(File.join(intent_dir, "outcome.md")), "disposition: abandoned"
  end

  def test_future_abandon_prints_the_store_commit_instruction
    file_under("Future")
    store_dir = File.join(@global, "store")

    status, out, err = plastic(*ABANDON)

    assert_equal 0, status, err
    assert_match(
      /git -C #{Regexp.escape(store_dir)} add -- .*git -C #{Regexp.escape(store_dir)} commit -m "chore: complete intent 1 \(abandoned\)"/m,
      out
    )
    [intent_dir, @index].each { |path| assert_includes out, path }
  end

  def test_a_second_close_of_a_closed_future_intent_changes_nothing
    file_under("Future")
    plastic(*ABANDON)
    before = snapshot

    status, _out, err = plastic(*ABANDON)

    assert_equal 0, status, err
    assert_equal before, snapshot
  end

  def test_an_absent_index_entry_refuses_the_preview_without_writing
    file_under(nil)
    before = snapshot

    status, _out, err = plastic(*ABANDON, "--dry-run")

    assert_equal 1, status, err
    assert_includes err, "intent 1 could not be resolved"
    assert_equal before, snapshot
  end

  def test_an_absent_index_entry_refuses_the_close_before_the_backfill
    file_under(nil)
    before = snapshot

    status, _out, err = plastic(*ABANDON)

    assert_equal 1, status, err
    assert_includes err, "intent 1 could not be resolved"
    assert_equal before, snapshot
  end

  def test_a_malformed_index_entry_refuses_preview_and_close_without_writing
    file_under("Future")
    File.write(@index, File.read(@index).sub(%r{\]\(store/1--later/1--later\.md\)}, "]"))
    before = snapshot

    preview_status, = plastic(*ABANDON, "--dry-run")
    status, _out, err = plastic(*ABANDON)

    assert_equal [1, 1], [preview_status, status], err
    assert_equal before, snapshot
  end

  def test_a_future_untouched_scaffold_still_refuses_a_delivered_close
    file_under("Future")
    before = snapshot

    preview_status, = plastic("intent", "end", "1", "--delivered", "--summary", "shipped", "--dry-run")
    status, _out, err = plastic("intent", "end", "1", "--delivered", "--summary", "shipped")

    assert_equal [1, 1], [preview_status, status]
    assert_includes err, "untouched scaffold"
    assert_equal before, snapshot
  end

  def test_a_worked_future_intent_delivers_like_an_active_one
    File.write(File.join(intent_dir, "checklist.md"), "# Checklist: later\n\n- [x] S1 the change\n")
    file_under("Future")

    preview_status, preview_out, = plastic("intent", "end", "1", "--delivered", "--summary", "shipped", "--dry-run")
    status, _out, err = plastic("intent", "end", "1", "--delivered", "--summary", "shipped")

    assert_equal [0, 0], [preview_status, status], err
    assert_includes preview_out, "from ## Future to ## Completed"
    assert_equal "Completed", section_of("1")
  end
end
