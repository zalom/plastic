# frozen_string_literal: true

module Plastic
  class TestCase
    # The graphs of the global store of the test's home, and reads of the
    # files they print.
    module StoreHelper
      def store_root = File.join(@plastic_home, "stores", "global")

      def store_path(path) = File.join(store_root, path)

      # The row store/index.json lists for an intent, nil when it lists none.
      def listed(id) = JSON.parse(File.read(store_path("store/index.json"))).fetch("intents").find { |row| row.fetch("intent_id") == id }

      def store_graphs = Plastic::Graph.open(home: @plastic_home, store: "global")

      def origin = Plastic::Graph::Origin.new(@plastic_home).id

      def folder = Plastic::Graph::Knowledge::StoreFolder.new(store_root)

      def write(path, text) = folder.write(path, text)

      def retrieval = store_graphs.retrieval

      # A new intent with its files printed, as plastic intent new leaves it.
      def open_intent(title = "Alpha", **fields)
        work = store_graphs.work
        intent = work.write_intent(title:, **fields)
        work.print_intent(intent.intent_id)
        intent
      end

      # An open intent whose synced spec.md holds one done criterion, so a node can name its key.
      def open_keyed_intent(title = "Alpha", key: "done", **fields)
        intent = open_intent(title, **fields)
        write("#{intent.dir}/spec.md", "# Spec\n\n## Done criteria\n- [ ] [#{key}] it is done\n")
        sync_up
        intent
      end

      # Reads every changed file of the store into its rows, as plastic sync up does.
      def sync_up
        work = store_graphs.work
        work.sync_apply(work.sync_plan(:up, {}))
      end

      # Writes the rows one read adds, in the database that owns them.
      def apply_read(read) = store_graphs.databases.fetch(read.database).transaction { |batch| batch.apply([read.apply]) }

      # The one item of a list, asserted to be the only one.
      def sole(list)
        assert_equal 1, list.size, list.inspect
        list.first
      end

      # Every file under `dir` with its bytes, dot files included.
      def snapshot(dir)
        files = Dir.glob("**/*", File::FNM_DOTMATCH, base: dir).select { |rel| File.file?(File.join(dir, rel)) }
        files.sort.to_h { |rel| [rel, File.binread(File.join(dir, rel))] }
      end
    end
  end
end
