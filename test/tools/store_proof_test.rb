# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../tools/store_proof"
require "sqlite3"
require "stringio"
require "tmpdir"
require "fileutils"

# The proof wrapper runs a command against copies of the real stores and
# proves the real files stayed as they were. Every test uses a throwaway
# folder as the real home and another as the job tmp.
module StoreProofHomes
  FILES = %w[local.db stores/plastic/work_graph.db stores/plastic/knowledge_graph.db stores/plastic/references.db].freeze

  def setup
    @root = Dir.mktmpdir("store-proof")
    @real = File.join(@root, "real")
    @job = File.join(@root, "job")
    FileUtils.mkdir_p([@real, @job])
    FILES.each { |file| make_database(File.join(@real, file)) }
    File.write(File.join(@real, "VERSION"), "3.0.0-alpha.1\n")
  end

  def teardown = FileUtils.rm_rf(@root)

  def make_database(path)
    FileUtils.mkdir_p(File.dirname(path))
    SQLite3::Database.new(path) { |db| db.execute_batch("CREATE TABLE notes (id INTEGER PRIMARY KEY, body TEXT); INSERT INTO notes (body) VALUES ('kept');") }
  end

  def set_version(file, number) = SQLite3::Database.new(File.join(@real, file)) { |db| db.execute("PRAGMA user_version = #{number}") }

  def run_cli(*argv, runner: ->(_env, _command) { true })
    out = StringIO.new
    err = StringIO.new
    code = StoreProof::CLI.new(argv, out:, err:, runner:).call
    [code, out.string, err.string]
  end

  def proof_args(*command) = ["--job-tmp", @job, "--real-home", @real, "--", *command]
end

class StoreProofTest < Minitest::Test
  include StoreProofHomes

  def test_a_run_whose_paths_sit_under_the_job_tmp_runs_the_command_with_the_four_variables
    seen = nil
    code, = run_cli(*proof_args("plastic", "status"), runner: ->(env, command) { seen = [env, command] })

    assert_equal [0, %w[plastic status]], [code, seen.last]
    assert_equal %w[HOME PLASTIC_BIN PLASTIC_HOME PLASTIC_SHARE], seen.first.keys.sort
    assert(seen.first.values.all? { |path| path.start_with?(@job + File::SEPARATOR) })
  end

  def test_a_path_outside_the_job_tmp_aborts_with_no_copy_and_no_command_run
    ran = false
    outside = StoreProof::Environment.new(@job).to_h.merge("PLASTIC_HOME" => File.join(@root, "elsewhere"))

    assert_raises(StoreProof::Outside) { StoreProof::Guard.new(@job).check(outside) }
    code, _, err = run_cli("--job-tmp", @job, "--real-home", @real, "--plastic-home", File.join(@root, "elsewhere"), "--", "plastic", runner: ->(*) { ran = true })

    assert_equal [3, false], [code, ran]
    assert_includes err, "outside the job tmp"
  end

  def test_a_refused_path_leaves_no_copy_in_the_job_tmp
    run_cli("--job-tmp", @job, "--real-home", @real, "--plastic-home", File.join(@root, "elsewhere"), "--", "plastic")

    refute_path_exists File.join(@job, "plastic_home")
  end

  def test_a_path_that_climbs_out_with_dots_is_outside
    climbing = StoreProof::Environment.new(@job).to_h.merge("HOME" => File.join(@job, "..", "real"))

    assert_raises(StoreProof::Outside) { StoreProof::Guard.new(@job).check(climbing) }
  end

  def test_the_copies_hold_the_rows_of_the_real_files_and_pass_the_quick_check
    run_cli(*proof_args("plastic"))
    copy = File.join(@job, "plastic_home", "local.db")

    assert_equal [["kept"]], SQLite3::Database.new(copy).execute("SELECT body FROM notes")
    assert_equal [["ok"]], SQLite3::Database.new(copy).execute("PRAGMA quick_check")
  end

  def test_the_real_files_keep_their_bytes_after_the_copy
    before = FILES.to_h { |file| [file, File.binread(File.join(@real, file))] }
    run_cli(*proof_args("plastic"))

    assert_equal before, FILES.to_h { |file| [file, File.binread(File.join(@real, file))] }
  end
end

class StoreProofChecksTest < Minitest::Test
  include StoreProofHomes

  def test_a_real_file_whose_version_changed_during_the_run_fails_the_proof
    code, _, err = run_cli(*proof_args("plastic"), runner: ->(*) { set_version("stores/plastic/work_graph.db", 1) })

    assert_equal 1, code
    assert_includes err, "stores/plastic/work_graph.db has user_version 1"
  end

  def test_a_changed_version_record_fails_the_proof
    code, _, err = run_cli(*proof_args("plastic"), runner: ->(*) { File.write(File.join(@real, "VERSION"), "3.0.0-alpha.2\n") })

    assert_equal 1, code
    assert_includes err, "VERSION changed"
  end

  def test_a_real_file_that_is_not_at_version_zero_before_the_run_fails_the_proof
    set_version("local.db", 2)
    ran = false
    code, _, err = run_cli(*proof_args("plastic"), runner: ->(*) { ran = true })

    assert_equal [1, false], [code, ran]
    assert_includes err, "local.db has user_version 2"
  end

  def test_a_real_file_that_fails_the_quick_check_stops_the_proof_with_no_command_run
    File.write(File.join(@real, "local.db"), "not a database")
    ran = false
    code, _, err = run_cli(*proof_args("plastic"), runner: ->(*) { ran = true })

    assert_equal [1, false], [code, ran]
    assert_includes err, "local.db"
  end

  def test_a_failing_command_fails_the_proof_with_its_status
    code, = run_cli(*proof_args("plastic"), runner: ->(*) { false })

    assert_equal 1, code
  end

  def test_the_ten_fixed_search_phrases_are_ten_distinct_phrases
    assert_equal 10, StoreProof::PHRASES.size
    assert_equal StoreProof::PHRASES.size, StoreProof::PHRASES.uniq.size
    assert_predicate StoreProof::PHRASES, :frozen?
  end

  def test_a_real_file_that_is_missing_stops_the_proof_with_no_command_run
    File.delete(File.join(@real, "local.db"))
    ran = false
    code, = run_cli(*proof_args("plastic"), runner: ->(*) { ran = true })

    assert_equal [1, false], [code, ran]
  end

  def test_a_copy_target_that_already_exists_fails_the_proof
    FileUtils.mkdir_p(File.join(@job, "plastic_home"))
    File.write(File.join(@job, "plastic_home", "local.db"), "in the way")
    code, = run_cli(*proof_args("plastic"))

    assert_equal 1, code
  end

  def test_an_unknown_option_is_called_wrongly
    code, = run_cli("--bogus", *proof_args("plastic"))

    assert_equal 2, code
  end

  def test_a_command_given_with_no_separator_still_runs
    seen = nil
    run_cli("--job-tmp", @job, "--real-home", @real, "plastic", "status", runner: ->(_env, command) { seen = command })

    assert_equal %w[plastic status], seen
  end

  def test_the_runner_hands_the_spawner_only_the_given_variables_and_the_path
    seen = nil
    spawner = ->(env, *command, **options) { seen = [env, command, options] }
    env = StoreProof::Environment.new(@job).to_h
    StoreProof::CLI::Runner.new(spawner:, path: "/usr/bin").call(env, %w[plastic status])

    assert_equal [env.merge("PATH" => "/usr/bin"), %w[plastic status], { unsetenv_others: true }], seen
  end

  def test_the_runner_answers_what_the_spawner_answers
    refute StoreProof::CLI::Runner.new(spawner: ->(*, **) { false }, path: "").call({}, ["plastic"])
  end

  def test_every_store_under_the_stores_folder_is_copied
    make_database(File.join(@real, "stores", "other", "work_graph.db"))
    run_cli(*proof_args("plastic"))

    assert_equal %w[other plastic], Dir.children(File.join(@job, "plastic_home", "stores")).sort
    assert_equal [["kept"]], SQLite3::Database.new(File.join(@job, "plastic_home", "stores", "other", "work_graph.db")).execute("SELECT body FROM notes")
  end

  def test_a_store_database_that_is_missing_is_skipped_by_name_and_the_proof_passes
    File.delete(File.join(@real, "stores", "plastic", "references.db"))
    code, out, = run_cli(*proof_args("plastic"))

    assert_equal 0, code
    assert_includes out, "skipped stores/plastic/references.db: missing"
    refute_path_exists File.join(@job, "plastic_home", "stores", "plastic", "references.db")
  end

  def test_a_store_database_at_a_stamp_above_zero_fails_the_proof_whichever_store_holds_it
    make_database(File.join(@real, "stores", "other", "work_graph.db"))
    set_version("stores/other/work_graph.db", 4)
    code, _, err = run_cli(*proof_args("plastic"))

    assert_equal 1, code
    assert_includes err, "stores/other/work_graph.db has user_version 4"
  end

  def test_the_files_of_the_home_that_are_not_databases_are_copied_with_their_bytes
    File.write(File.join(@real, "config.yml"), "advisor: none\n")
    FileUtils.mkdir_p(File.join(@real, "stores", "plastic", "resources"))
    File.write(File.join(@real, "stores", "plastic", "resources", "note.md"), "kept\n")
    run_cli(*proof_args("plastic"))
    copied = File.join(@job, "plastic_home")
    contents = %w[config.yml stores/plastic/resources/note.md VERSION].map { |file| File.read(File.join(copied, file)) }

    assert_equal ["advisor: none\n", "kept\n", "3.0.0-alpha.1\n"], contents
    assert_empty Dir.glob(File.join(copied, "**", "*.db-{wal,shm,journal}"))
  end

  def test_the_job_tmp_must_be_given
    code, _, err = run_cli("--real-home", @real, "--", "plastic")

    assert_equal 2, code
    assert_includes err, "--job-tmp"
  end
end
