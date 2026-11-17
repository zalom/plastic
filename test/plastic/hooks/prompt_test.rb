# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/hooks/prompt"

class PromptTest < Plastic::TestCase
  fixtures :empty

  CLAUDE = { "CLAUDE_CODE_SESSION_ID" => "s-1" }.freeze
  FIXTURES = File.expand_path("../../fixtures/hooks", __dir__)

  def call(input = nil, env: CLAUDE, **event) = plastic("hook", "prompt", input: input || JSON.generate(event), env:, table: Plastic::CLI::TABLE)

  def messages = store_graphs.databases.fetch(:local).rows("SELECT session_id, harness, store, intent_id, role, text FROM chat_messages ORDER BY id")

  def start_claude_session = plastic("hook", "start", input: JSON.generate(source: "startup"), env: CLAUDE, table: Plastic::CLI::TABLE)

  def test_prints_nothing_on_stdout
    assert_call call(prompt: "hello"), code: 0, out: "", err: ""
  end

  def hold_node(intent_id, session)
    at = "2026-11-17T09:00:00Z"
    store_graphs.databases.fetch(:store).transaction do |batch|
      batch.put(:nodes, { intent_id:, id: "n1", state: "claimed", claimed_by: session, claimed_at: at, seen_at: at, updated_at: at })
    end
  end

  def test_records_the_prompt_with_session_store_and_intent
    start_claude_session
    intent = open_intent
    hold_node(intent.intent_id, "s-1")
    call(prompt: "hello")

    assert_equal [["s-1", "claude-code", "global", intent.intent_id, "user", "hello"]], messages.map(&:values)
  end

  def test_records_the_prompt_with_no_intent_when_the_session_holds_none
    start_claude_session
    call(prompt: "hello")

    assert_equal [["s-1", "claude-code", "global", nil, "user", "hello"]], messages.map(&:values)
  end

  def hook_in(home, input = JSON.generate(prompt: "alone"))
    environment = Plastic::CLI::Command::Environment.new(env: { "PLASTIC_HOME" => home, "PLASTIC_SESSION" => "s-1" },
      input: StringIO.new(input), out: StringIO.new, err: StringIO.new, home: File.dirname(home), directory: File.dirname(home))
    [Plastic::Hooks::Prompt.call([], environment:), environment.err.string]
  end

  def test_a_prompt_with_no_store_is_recorded_with_store_and_intent_empty
    with_home(global: false) do |home|
      code, = hook_in(home)
      rows = Plastic::Graph::Database.open_local(home).fetch(:local).rows("SELECT store, intent_id, text FROM chat_messages")

      assert_equal [0, [{ "store" => nil, "intent_id" => nil, "text" => "alone" }]], [code, rows]
    end
  end

  def test_an_event_with_no_session_records_nothing_and_exits_zero
    assert_call call(env: {}, prompt: "hello"), code: 0, out: "", err: "plastic hook: the event names no session; nothing recorded\n"
    assert_empty messages
  end

  def test_an_event_with_no_prompt_records_nothing
    assert_call call, code: 0, out: "", err: "plastic hook: the event carries no prompt; nothing recorded\n"
    assert_empty messages
  end

  def test_a_refused_write_exits_zero_and_says_so_on_stderr
    store_graphs.databases.fetch(:local).transaction { |batch| batch.add("CREATE TRIGGER refuse BEFORE INSERT ON chat_messages BEGIN SELECT RAISE(ABORT, 'write refused'); END") }
    result = call(prompt: "hello")

    assert_equal [0, "", true], [result.code, result.out, result.err.start_with?("plastic hook:")]
  end

  def test_reads_both_harness_fixtures
    %w[claude_code_prompt_submit.json codex_prompt_submit.documented.json].each { |name| call(File.read(File.join(FIXTURES, name)), env: {}) }

    assert_equal ["Reply with the word ready."] * 2, messages.map { |row| row["text"] }
  end

  def test_a_home_with_the_former_local_db_exits_zero_and_says_so_on_stderr
    with_home(global: false) do |home|
      FileUtils.mkdir_p(home)
      File.write(File.join(home, "local.db"), "")
      code, err = hook_in(home)

      assert_equal [0, true], [code, err.include?("local.db is not migrated")]
    end
  end
end
