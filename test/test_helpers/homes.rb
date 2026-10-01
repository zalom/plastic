# frozen_string_literal: true

require "yaml"

module Plastic
  class TestCase
    # The homes the tests run in, one per fixture per process, built from its
    # file under test/fixtures/homes: the store databases with their schema,
    # the origin id, and the intents and files the fixture lists. A test runs
    # inside a transaction on each database of its home and rolls it back,
    # as a Rails test does; the files it changed are put back after it.
    module Homes
      FIXTURES = File.expand_path("../fixtures", __dir__)

      def self.template(name)
        @templates = {} unless @pid == Process.pid
        @pid = Process.pid
        @templates[name] ||= Home.build(name)
      end

      # One built home: its folder, its database files and a copy of the rest.
      class Home
        Pool = Plastic::Graph::Database::ConnectionPool

        attr_reader :dir

        def self.build(name)
          dir = File.realpath(Dir.mktmpdir("plastic-home-#{name}"))
          Minitest.after_run { FileUtils.rm_rf([dir, "#{dir}.files"]) }
          Fixture.new(File.join(dir, ".plastic"), YAML.load_file(File.join(FIXTURES, "homes", "#{name}.yml"))).load
          new(dir)
        end

        def initialize(dir)
          @dir = dir
          @databases = Dir.glob("#{dir}/**/*.db", File::FNM_DOTMATCH)
          @files = "#{dir}.files"
          FileUtils.cp_r(dir, @files)
          Dir.glob("#{@files}/**/*.db", File::FNM_DOTMATCH).each { |path| File.delete(path) }
        end

        def begin = connections.each { |connection| connection.execute("BEGIN") }

        # Rolls each database back, closes every other connection and puts the files back.
        def reset
          connections.each { |connection| connection.rollback if connection.transaction_active? }
          Pool.disconnect(keep: @databases)
          Dir.glob("**/*", File::FNM_DOTMATCH, base: @dir).reverse_each { |entry| clear(File.join(@dir, entry)) }
          FileUtils.cp_r("#{@files}/.", @dir)
        end

        private

        def connections = @databases.map { |path| Pool.for(path) }

        def clear(path)
          return if @databases.include?(path) || File.basename(path) == "."

          return File.delete(path) if File.symlink?(path) || !File.directory?(path)

          Dir.rmdir(path) if Dir.empty?(path)
        end
      end

      # One home fixture loaded through the kernel's own public calls.
      class Fixture
        def initialize(plastic_home, data)
          @plastic_home = plastic_home
          @data = data || {}
        end

        def load
          copy_store
          graphs.databases.each_value { |database| database.rows("SELECT 1") }
          @data.fetch("intents", []).each { |intent| open_intent(intent) }
          sync_up if @data["sync"]
        end

        private

        def store_root = File.join(@plastic_home, "stores", "global")

        def graphs = Plastic::Graph.open(home: @plastic_home, store: "global")

        def folder = Plastic::Graph::StoreFolder.new(store_root)

        def copy_store
          store = @data["store"] or return
          FileUtils.mkdir_p(File.dirname(store_root))
          FileUtils.cp_r(File.join(FIXTURES, store), store_root)
        end

        def open_intent(fields)
          work = graphs.work
          intent = work.write_intent(title: fields.fetch("title"))
          work.print_intent(intent.intent_id)
          fields.fetch("files", {}).each { |name, text| folder.write("#{intent.dir}/#{name}", text) }
        end

        def sync_up
          current = graphs
          sync = Plastic::Graph::Sync.new(folder:, retrieval: current.retrieval, databases: current.databases)
          sync.apply(sync.plan(:up, {}))
        end
      end
    end
  end
end
