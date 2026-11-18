# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"
require "stringio"
require "tmpdir"

load File.expand_path("../bin/verify-change", __dir__) unless defined?(VerifyChange)

# The gate reads the migrations at the tip of the base it is given and at HEAD through its git lambda, and fails
# when the migration guard finds a problem, whatever the other checks answer.
class VerifyChangeMigrationGuardTest < Minitest::Test
  FOLDER = MigrationGuard::FOLDER
  BASELINE = "#{FOLDER}/store/20261117000000_store_from_beta_2.sql".freeze
  LATER = "#{FOLDER}/store/20261201000000_add_owners.sql".freeze
  Status = Struct.new(:success?)

  def setup
    @root = Dir.mktmpdir("verify-change-migrations")
    @err = StringIO.new
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  # A git that holds the given migration files at each ref and no changed Ruby file.
  def git(refs)
    lambda do |*args|
      case args
      in ["ls-tree", "-r", "--name-only", ref, "--", FOLDER] then [refs.fetch(ref).keys.join("\n"), Status.new(true)]
      in ["show", spec] then ref, path = spec.split(":", 2)
                             [refs.fetch(ref).fetch(path), Status.new(true)]
      in ["merge-base", *] then ["abc123\n", Status.new(true)]
      else ["", Status.new(true)]
      end
    end
  end

  def gate(refs) = VerifyChange.new(["origin/alpha"], root: @root, out: StringIO.new, err: @err, git: git({ "abc123" => refs.fetch("origin/alpha") }.merge(refs))).call

  def test_a_changed_merged_migration_fails_the_gate_and_is_named
    code = gate("origin/alpha" => { BASELINE => "CREATE TABLE a (id INTEGER);\n" }, "HEAD" => { BASELINE => "CREATE TABLE a (id TEXT);\n" })

    assert_equal [1, true], [code, @err.string.include?("#{BASELINE} is a merged migration")]
  end

  def test_unchanged_migrations_pass_the_gate
    files = { BASELINE => "CREATE TABLE a (id INTEGER);\n" }

    assert_equal [0, ""], [gate("origin/alpha" => files, "HEAD" => files), @err.string]
  end

  def test_a_base_with_no_migration_folder_passes_the_gate
    assert_equal 0, gate("origin/alpha" => {}, "abc123" => {}, "HEAD" => { BASELINE => "CREATE TABLE a (id INTEGER);\n" })
  end

  def test_a_migration_merged_after_the_branch_was_cut_asks_for_a_rebase_and_is_not_called_deleted
    files = { BASELINE => "CREATE TABLE a (id INTEGER);\n" }
    code = gate("origin/alpha" => files.merge(LATER => "ALTER TABLE a ADD COLUMN b TEXT;\n"), "abc123" => files, "HEAD" => files)

    assert_equal [1, true, false], [code, @err.string.include?("#{LATER} was merged to the base after this branch was cut; rebase onto the base"),
      @err.string.include?("changed, renamed or deleted")]
  end

  def test_a_migration_this_branch_deleted_is_named_as_deleted
    files = { BASELINE => "CREATE TABLE a (id INTEGER);\n", LATER => "ALTER TABLE a ADD COLUMN b TEXT;\n" }
    code = gate("origin/alpha" => files, "abc123" => files, "HEAD" => files.except(LATER))

    assert_equal [1, true], [code, @err.string.include?("#{LATER} is a merged migration and was changed, renamed or deleted")]
  end
end
