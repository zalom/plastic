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

      # One built home: its folder, a snapshot of every file it started with,
      # and the state of each one. A reset compares that
      # state with what the home holds now and touches only what moved,
      # instead of copying the whole fixture back on every test.
      class Home
        Pool = Plastic::Graph::Database::ConnectionPool
        DATABASE_PATTERN, JOURNAL_PATTERN = Plastic::Graph::Knowledge::StoreFolder::IGNORED

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
          FileUtils.cp_r(dir, @files, preserve: true)
          [DATABASE_PATTERN, JOURNAL_PATTERN].each do |pattern|
            Dir.glob("#{@files}/**/#{pattern}", File::FNM_DOTMATCH).each { |path| File.delete(path) }
          end
          @snapshot = Snapshot.new(@databases)
          @state = @snapshot.scan(dir)
        end

        def begin = connections.each { |connection| connection.execute("BEGIN") }

        # Rolls each database back, closes every other connection, removes
        # what is new and puts back only what is missing or different from
        # the state recorded in `initialize`.
        def reset
          rollback
          current = @snapshot.scan(@dir)
          remove_new(current)
          restore_changed(current)
        end

        private

        def rollback
          connections.each { |connection| connection.rollback if connection.transaction_active? }
          Pool.disconnect(keep: @databases)
        end

        def remove_new(current)
          (current.keys - @state.keys).sort.reverse_each { |rel| clear(File.join(@dir, rel)) }
        end

        def restore_changed(current)
          @state.sort.each do |rel, original|
            next if current[rel] == original

            restore(rel, original)
            @state[rel] = @snapshot.entry(File.join(@dir, rel))
          end
        end

        def connections = @databases.map { |path| Pool.for(path) }

        def clear(full)
          stat = File.lstat(full)
          return File.delete(full) if stat.symlink? || !stat.directory?

          Dir.rmdir(full) if Dir.empty?(full)
        rescue Errno::ENOENT
          nil
        end

        def restore(rel, original)
          full = File.join(@dir, rel)
          remove_if_present(full) unless current_type(full) == original.type
          case original.type
          when :dir then restore_dir(full, original)
          when :link then restore_link(full, original)
          else restore_file(rel, full)
          end
        end

        def current_type(full)
          return nil unless File.exist?(full) || File.symlink?(full)

          stat = File.lstat(full)
          return :link if stat.symlink?
          return :dir if stat.directory?

          :file
        end

        def remove_if_present(full)
          stat = File.lstat(full)
          (stat.directory? && !stat.symlink?) ? FileUtils.rm_rf(full) : File.delete(full)
        rescue Errno::ENOENT
          nil
        end

        def restore_dir(full, original)
          FileUtils.mkdir_p(full)
          File.chmod(original.mode, full)
        end

        def restore_link(full, original)
          File.delete(full) if File.symlink?(full)
          File.symlink(original.target, full)
        end

        def restore_file(rel, full)
          FileUtils.mkdir_p(File.dirname(full))
          FileUtils.cp(File.join(@files, rel), full, preserve: true)
        end
      end

      # The state of every entry under a home's folder, by path relative to
      # it: type, size, mode, change time and link target, without following
      # a link. Skips a tracked database (left to the transaction rollback)
      # and any journal of one. A symlinked directory is recorded but never
      # entered, so a link outside the home is never followed into.
      class Snapshot
        Entry = Struct.new(:type, :size, :mode, :ctime, :target)

        def initialize(databases)
          @databases = databases
        end

        def scan(base)
          state = {}
          walk(base) { |rel, full| state[rel] = entry(full) unless skip?(rel, full) }
          state
        end

        def entry(full)
          stat = File.lstat(full)
          return Entry.new(:link, nil, nil, stat.ctime, File.readlink(full)) if stat.symlink?
          return Entry.new(:dir, nil, stat.mode & 0o7777, stat.ctime, nil) if stat.directory?

          Entry.new(:file, stat.size, stat.mode & 0o7777, stat.ctime, nil)
        end

        private

        def walk(base, rel = "", &block)
          Dir.children(File.join(base, rel)).sort.each do |name|
            child = rel.empty? ? name : File.join(rel, name)
            full = File.join(base, child)
            block.call(child, full)
            walk(base, child, &block) if File.directory?(full) && !File.symlink?(full)
          end
        end

        # A rollback journal is never tracked, new or not. A database file is
        # tracked only when it was already part of the home at build time; an
        # untracked one is a new file a test made, so it is scanned and,
        # being absent from the recorded state, removed like any other new
        # entry.
        def skip?(rel, full)
          basename = File.basename(rel)
          return true if File.fnmatch?(Home::JOURNAL_PATTERN, basename)

          File.fnmatch?(Home::DATABASE_PATTERN, basename) && @databases.include?(full)
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
          FileUtils.mkdir_p(store_root)
          graphs.databases.each_value { |database| database.rows("SELECT 1") }
          @data.fetch("intents", []).each { |intent| open_intent(intent) }
          sync_up if @data["sync"]
        end

        private

        def store_root = File.join(@plastic_home, "stores", "global")

        def graphs = Plastic::Graph.open(home: @plastic_home, store: "global")

        def folder = Plastic::Graph::Knowledge::StoreFolder.new(store_root)

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
          sync = Plastic::Graph::Knowledge::Sync.new(folder:, retrieval: current.retrieval, databases: current.databases)
          sync.apply(sync.plan(:up, {}))
        end
      end
    end
  end
end
