# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../tools/search_check"
require "digest"
require "fileutils"
require "json"
require "sqlite3"
require "stringio"
require "tmpdir"

# The known-question check reads a question file and a store's search index, and prints one line per question and a
# total. Every test builds a small store of three intents in a throwaway folder; no store content is in the repository.
class SearchCheckTest < Minitest::Test
  ORIGIN = "o1"
  DOCUMENTS = {
    "10" => "the ownership lease lapses after fifteen minutes without renewal",
    "20" => "the status bar command chained with another command broke",
    "30" => "installing third party skills from a marketplace carries risk"
  }.freeze

  def setup
    @root = Dir.mktmpdir("search-check")
    @store = File.join(@root, "stores", "plastic")
    FileUtils.mkdir_p(@store)
    build_store
    @questions = File.join(@root, "questions.json")
  end

  def teardown = FileUtils.rm_rf(@root)

  def build_store
    SQLite3::Database.new(File.join(@store, "knowledge_graph.db")) do |db|
      db.execute("CREATE TABLE document_heads (intent_id, path, sha256, updated_at, origin_id)")
      DOCUMENTS.each_key { |id| db.execute("INSERT INTO document_heads VALUES (?, 'spec.md', ?, 'x', ?)", [id, "sha#{id}", ORIGIN]) }
    end
    SQLite3::Database.new(File.join(@store, "retrieval_graph.db")) do |db|
      db.execute("CREATE VIRTUAL TABLE document_fts USING fts5(body, intent_id UNINDEXED, path UNINDEXED, sha256 UNINDEXED, position UNINDEXED, origin_id UNINDEXED)")
      DOCUMENTS.each { |id, body| db.execute("INSERT INTO document_fts VALUES (?, ?, 'spec.md', ?, 0, ?)", [body, id, "sha#{id}", ORIGIN]) }
    end
  end

  def write_questions(rows) = File.write(@questions, JSON.generate(rows))

  def question(id, text, answers, keywords: text)
    { "id" => id, "question" => text, "keywords" => keywords, "answers" => answers, "source" => "agent 10" }
  end

  def run_cli(*argv)
    out = StringIO.new
    err = StringIO.new
    code = SearchCheck::CLI.new([*argv], out:, err:, home: @root).call
    [code, out.string, err.string]
  end

  def checksums = Dir.glob(File.join(@store, "*"), File::FNM_DOTMATCH).select { File.file?(_1) }.sort.to_h { [File.basename(_1), Digest::SHA256.file(_1).hexdigest] }

  def test_prints_one_line_for_each_question_and_a_total
    write_questions([question("q1", "how long does the lease last", ["10"]), question("q2", "chained status bar", ["20"]), question("q3", "unrelated zebra", ["30"])])
    code, out, err = run_cli(@questions)
    assert_equal [0, ""], [code, err]
    assert_equal 4, out.lines.size
    assert_match(/\Aq1 +hit +rank 1/, out.lines[0])
    assert_match(/\Aq3 +miss/, out.lines[2])
    assert_match(%r{total 2/3}, out.lines.last)
  end

  def test_counts_a_hit_when_any_listed_answer_is_in_the_first_five
    write_questions([question("q1", "marketplace skills risk", %w[10 30])])
    _code, out, = run_cli(@questions)
    assert_match(/q1 +hit +rank 1/, out)
  end

  def test_with_keywords_it_searches_the_keywords_instead_of_the_question
    write_questions([question("q1", "zebra zebra", ["10"], keywords: "lease renewal")])
    assert_match(%r{total 0/1}, run_cli(@questions)[1])
    assert_match(%r{total 1/1}, run_cli(@questions, "--keywords")[1])
  end

  def test_the_limit_sets_how_many_intents_count
    write_questions([question("q1", "command lease marketplace", ["30"])])
    assert_match(/q1 +hit/, run_cli(@questions, "--limit", "3")[1])
    assert_match(/q1 +miss/, run_cli(@questions, "--limit", "1")[1])
  end

  def test_a_run_writes_nothing_to_the_store
    write_questions([question("q1", "lease", ["10"])])
    before = checksums
    run_cli(@questions)
    assert_equal before, checksums
  end

  def test_a_missing_question_file_exits_2_with_a_message_and_no_output
    code, out, err = run_cli(File.join(@root, "absent.json"))
    assert_equal [2, ""], [code, out]
    assert_match(/absent\.json/, err)
  end

  def test_a_missing_store_exits_2_and_creates_no_file
    write_questions([question("q1", "lease", ["10"])])
    code, _out, err = run_cli(@questions, "--store", File.join(@root, "nowhere"))
    assert_equal 2, code
    assert_match(/nowhere/, err)
    refute File.exist?(File.join(@root, "nowhere"))
  end
end
