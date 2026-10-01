# frozen_string_literal: true

require "yaml"

module Plastic
  class TestCase
    # The homes the tests copy. Each is built once per process from its file
    # under test/fixtures/homes: the store databases with their schema, the
    # origin id, and the intents and files the fixture lists.
    module Homes
      FIXTURES = File.expand_path("../fixtures", __dir__)

      def self.template(name) = (@templates ||= {})[name] ||= build(name)

      def self.build(name)
        dir = File.realpath(Dir.mktmpdir("plastic-home-#{name}"))
        Minitest.after_run { FileUtils.remove_entry(dir) }
        Fixture.new(File.join(dir, ".plastic"), YAML.load_file(File.join(FIXTURES, "homes", "#{name}.yml"))).load
        dir
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
          Plastic::Graph::Database::Program.disconnect
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
