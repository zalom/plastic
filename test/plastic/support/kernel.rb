# frozen_string_literal: true

require_relative "../../test_helper"
require "fileutils"
require "securerandom"
require "sqlite3"
require "stringio"
require "tmpdir"
require_relative "../../../scripts/lib/plastic"

# Routines and workflows that exist only for the kernel tests. They live in
# their own namespace, with their own registry and command table, so no test
# adds a key to Plastic::Workflows::REGISTRY or Plastic::CLI::TABLE.
module KernelFixtures
  module Workflows
    REGISTRY = %i[code_stamp code_greet code_find_draft agent_write_draft code_hold code_hole
      code_break code_stuck agent_review code_who code_choose agent_greet].freeze

    class Stamp < Plastic::CodeWorkflow
      sets :stamp

      step "stamp the call", done: ->(c) { !c.stamp.nil? } do |c|
        c[:stamp] = SecureRandom.hex(4)
      end
    end

    class Greet < Plastic::CodeWorkflow
      sets :greeting

      read "greet" do |c|
        c[:greeting] = "hello #{c.name}"
        c.print(c.greeting)
      end

      outcome :done, offers: "plastic kernel two %{name}", because: "greeted %{name}"
    end

    class FindDraft < Plastic::CodeWorkflow
      sets :draft_path

      read "find the draft" do |c|
        c[:draft_path] = File.join(c.dir, "#{c.name}.md")
      end
    end

    class WriteDraft < Plastic::AgentWorkflow
      step "write", done: ->(c) { File.exist?(c.draft_path) }, say: "Write the draft to %{draft_path}"

      outcome :handoff, offers: "plastic kernel draft %{name}", because: "the draft for %{name} is not written yet"
      outcome :done, because: "the draft for %{name} is written, stamped %{stamp}"
    end

    class Hold < Plastic::CodeWorkflow
      gate "the owner holds %{mode}", stops: :refusal, pass: ->(c) { c.mode != "hold" }
      gate "the check broke on %{mode}", stops: :failure, pass: ->(c) { c.mode != "break" }

      outcome :done, because: "passed %{mode}"
    end

    class Hole < Plastic::CodeWorkflow
      sets :missing

      outcome :done, because: "found %{missing}"
    end

    class Break < Plastic::CodeWorkflow
      step "explode", done: ->(_c) { false } do |_c|
        raise "boom"
      end

      outcome :done, because: "exploded"
    end

    class Stuck < Plastic::CodeWorkflow
      step "never lands", done: ->(_c) { false } do |_c|
        nil
      end

      outcome :done, because: "landed"
    end

    class Review < Plastic::AgentWorkflow
      step "review", done: ->(_c) { false }, say: "Review the change"

      outcome :handoff, because: "the review is open", stops: :failure
      outcome :done, because: "reviewed"
    end

    class Who < Plastic::CodeWorkflow
      read "who" do |c|
        c.print("session #{c.session.inspect}")
      end

      outcome :done, because: "named the session"
    end

    class Choose < Plastic::CodeWorkflow
      outcome :yes, if: ->(_c) { true }, because: "chose yes"
    end
  end

  class Routine < Plastic::Routine
    def self.workflows = Workflows
  end

  class TwoStep < Routine
    argument :name, label: "NAME", text: "who to greet"

    workflow :code_stamp, next: :code_greet
    workflow :code_greet, next: :noop
  end

  class Draft < Routine
    subject :name
    argument :name, label: "NAME", text: "the draft's name"
    option :dir, switch: "--dir DIR", text: "where the draft goes"
    writes :work

    workflow :code_stamp, next: :code_find_draft
    workflow :code_find_draft, next: :agent_write_draft
    workflow :agent_write_draft, next: :noop
  end

  class Gate < Routine
    argument :mode, label: "MODE", text: "pass, hold or break"
    writes :work

    workflow :code_hold, next: :noop
  end

  class Holed < Routine
    workflow :code_hole, next: :noop
  end

  class Broken < Routine
    workflow :code_break, next: :noop
  end

  class Stalled < Routine
    workflow :code_stuck, next: :noop
  end

  class Reviewed < Routine
    workflow :agent_review, next: :noop
  end

  class Named < Routine
    workflow :code_who, next: :noop
  end

  class Backward < Routine
    workflow :code_stamp, next: :code_greet
    workflow :code_greet, next: :code_stamp
  end

  class Echo < Plastic::Hook
    def respond(event) = "session #{event[:session_id]}"
  end

  class Quiet < Plastic::Hook
    def respond(_event) = nil
  end

  TABLE = {
    "kernel two" => ["KernelFixtures::TwoStep", "Greet in two steps"],
    "kernel draft" => ["KernelFixtures::Draft", "Hand a draft to the agent"],
    "kernel gate" => ["KernelFixtures::Gate", "Stop at a gate"],
    "kernel hole" => ["KernelFixtures::Holed", "Close on a fact with no value"],
    "kernel break" => ["KernelFixtures::Broken", "Raise inside a step"],
    "kernel stuck" => ["KernelFixtures::Stalled", "Run a step that never lands"],
    "kernel review" => ["KernelFixtures::Reviewed", "Hand off as a failure"],
    "kernel backward" => ["KernelFixtures::Backward", "Point an edge backward"],
    "kernel who" => ["KernelFixtures::Named", "Print the session"],
    "hook echo" => ["KernelFixtures::Echo", "Echo the session"],
    "hook quiet" => ["KernelFixtures::Quiet", "Say nothing"]
  }.freeze

  # One call of the kernel command line, against a temporary home.
  module Calls
    Result = Data.define(:out, :err, :code)

    def make_home
      @home = Dir.mktmpdir("plastic-kernel")
      @plastic_home = File.join(@home, ".plastic")
      FileUtils.mkdir_p(@plastic_home)
    end

    def remove_home = FileUtils.remove_entry(@home)

    def environment(env: {}, input: "", out: StringIO.new, err: StringIO.new)
      Plastic::CLI::Command::Environment.new(env: { "PLASTIC_HOME" => @plastic_home }.merge(env),
        input: StringIO.new(input), out:, err:, home: @home, directory: @home)
    end

    def plastic(*argv, env: {}, input: "", table: TABLE)
      out = StringIO.new
      err = StringIO.new
      code = Plastic::CLI.call(argv, environment: environment(env:, input:, out:, err:), table:)
      Result.new(out.string, err.string, code)
    end

    def routine_run(tool, subject)
      Plastic::Graph.open(home: @plastic_home, store: "global").retrieval.routine_run(tool, subject)
    end
  end
end

module KernelFixtures
  # Builders for the workflow tests: a context and anonymous workflow classes.
  module WorkflowBuilders
    Flows = KernelFixtures::Workflows

    def context(declared: %i[name mode], facts: { name: "ada" })
      Plastic::Context.new(declared:, facts:, graphs: {})
    end

    def code(&body) = Class.new(Plastic::CodeWorkflow, &body)

    def agent(&body) = Class.new(Plastic::AgentWorkflow, &body)
  end

  # The sqlite3 library inside the test process, with one database in
  # memory per path: the same SQL as the sqlite3 program, and no process
  # for each script.
  class MemoryEngine
    def initialize = @databases = {}

    def check = nil

    def call(path, script)
      database = (@databases[path] ||= SQLite3::Database.new(":memory:", results_as_hash: true))
      result_sets(database, script)
    rescue SQLite3::Exception => error
      database.rollback if database.transaction_active?
      raise Plastic::Graph::Database::Error, "#{File.basename(path)}: #{error.message}"
    end

    private

    # Like the program: one set per statement that returns rows.
    def result_sets(database, script)
      sets = []
      rest = script
      until rest.strip.empty?
        statement = database.prepare(rest)
        sets << statement.execute.to_a
        rest = statement.remainder
        statement.close
      end
      sets.reject(&:empty?)
    end
  end

  # A database in memory, with tables for the database tests.
  module DatabaseHome
    Database = Plastic::Graph::Database
    SQL = Plastic::Graph::SQL
    SCHEMA = <<~SQL
      CREATE TABLE IF NOT EXISTS routine_runs(id INTEGER PRIMARY KEY, name TEXT UNIQUE, data BLOB);
      CREATE TABLE IF NOT EXISTS tallies(name TEXT);
      CREATE TABLE IF NOT EXISTS notes(name TEXT);
      CREATE TABLE IF NOT EXISTS stored(store TEXT, name TEXT);
    SQL

    def setup
      @database = Database.new("/memory/work_graph.db", SCHEMA, engine: MemoryEngine.new)
    end

    def insert(name, table: :routine_runs)
      @database.transaction { |batch| batch.insert(table, { name: }) }
    end
  end
end

module KernelFixtures
  # The graphs of the global store of a temporary home, on databases in
  # memory, and reads of the files they print.
  module StoreGraphs
    LEGACY_STORE = File.expand_path("../fixtures/legacy_store", __dir__)

    def setup
      @home = Dir.mktmpdir("plastic-store")
      @plastic_home = File.join(@home, ".plastic")
    end

    def teardown = FileUtils.remove_entry(@home)

    def engine = (@engine ||= MemoryEngine.new)

    def store_root = File.join(@plastic_home, "stores", "global")

    def store_path(path) = File.join(store_root, path)

    def store_graphs = Plastic::Graph.open(home: @plastic_home, store: "global", engine:)

    def origin = Plastic::Graph::Origin.new(@plastic_home).id

    def folder = Plastic::Graph::StoreFolder.new(store_root)

    def write(path, text) = folder.write(path, text)

    def retrieval = store_graphs.retrieval

    # A new intent with its files printed, as plastic intent new leaves it.
    def open_intent(title = "Alpha", **fields)
      work = store_graphs.work
      intent = work.write_intent(title:, **fields)
      work.print_intent(intent.intent_id)
      intent
    end

    # Writes the rows one read adds, in the database that owns them.
    def apply_read(read) = store_graphs.databases.fetch(read.database).transaction { |batch| batch.apply([read.apply]) }

    # The one item of a list, asserted to be the only one.
    def sole(list)
      assert_equal 1, list.size, list.inspect
      list.first
    end

    def copy_legacy_store
      FileUtils.mkdir_p(File.dirname(store_root))
      FileUtils.cp_r(LEGACY_STORE, store_root)
    end

    # Every file under `dir` with its bytes, dot files included.
    def snapshot(dir)
      files = Dir.glob("**/*", File::FNM_DOTMATCH, base: dir).select { |rel| File.file?(File.join(dir, rel)) }
      files.sort.to_h { |rel| [rel, File.binread(File.join(dir, rel))] }
    end
  end
end
