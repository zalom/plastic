# frozen_string_literal: true

require "fileutils"
require_relative "sqlite"
require_relative "index_entry"
require_relative "store_discovery"

module Plastic
  module WorkGraph
    NAME = "work_graph.db"
    SCHEMA = <<~SQL
      CREATE TABLE intent(id TEXT, store TEXT, slug TEXT, status TEXT, title TEXT);
      CREATE TABLE ledger(intent_id TEXT, store TEXT, at TEXT, stage TEXT, text TEXT);
    SQL
    STATUSES = %w[active future completed abandoned].freeze
    LEDGER_LINE = /\A(\S+)\s{2,}(\S+)\s{2,}(.+)\z/

    def self.path(home)
      File.join(home, NAME)
    end

    def self.build(home)
      draft = "#{path(home)}.tmp"
      FileUtils.rm_f(draft)
      rows = StoreDiscovery.discover(home)[:stores].flat_map { |store| intents(store) + ledger(store) }
      Sqlite.call(draft, [SCHEMA, "BEGIN;", *rows, "COMMIT;"].join("\n"))
      File.rename(draft, path(home))
    end

    def self.intents(store)
      return [] unless File.exist?(store[:index])

      status = nil
      File.readlines(store[:index], chomp: true, encoding: "UTF-8").filter_map do |line|
        status = line.delete_prefix("## ").downcase if line.start_with?("## ")
        entry = STATUSES.include?(status) && IndexEntry.match(line)
        entry && insert("intent", entry[1], store[:slug], File.basename(File.dirname(entry[3])).split("--", 2).last, status, entry[2])
      end
    end

    def self.ledger(store)
      Dir.glob("*/savepoint.md", base: store[:store]).sort.flat_map do |file|
        id = file.split("--").first
        File.readlines(File.join(store[:store], file), chomp: true, encoding: "UTF-8").filter_map do |line|
          entry = line.match(LEDGER_LINE)
          entry && insert("ledger", id, store[:slug], entry[1], entry[2], entry[3])
        end
      end
    end

    def self.insert(table, *values)
      "INSERT INTO #{table} VALUES(#{values.map { |value| Sqlite.quote(value.to_s) }.join(", ")});"
    end

    def self.known(home)
      Sqlite.call(path(home), "SELECT store, id FROM intent;", readonly: true).map { |row| "#{row["store"]}:#{row["id"]}" }
    end
  end
end
