# frozen_string_literal: true

require "fileutils"
require_relative "store_layout"
require_relative "sqlite"
require_relative "lock"

module Plastic
  class StoresMove
    Refused = Class.new(StandardError)

    GLOBAL_ENTRIES = %w[store INDEX.md roadmaps].freeze
    PATH_COLUMNS = {"knowledge_graph.db" => %w[doc path], "references.db" => %w[sqlar name]}.freeze
    LOCKS = "{store,projects/*/store}/*/delivery.lock"

    def self.call(...)
      new(...).call
    end

    def initialize(home, qmd_index:, dry_run: false)
      @home = home
      @qmd_index = qmd_index
      @dry_run = dry_run
    end

    def call
      refuse
      plan = [["copy", copy]] + moves.map { |from, to| ["move", "#{from} -> #{to}"] } + rewrites.map { |file| ["rewrite", file] }
      run unless @dry_run
      plan
    end

    def copy
      "#{@home}-before-stores-move"
    end

    private

    def refuse
      raise Refused, "#{File.join(@home, "stores")}/ exists, so this home has moved already" if StoreLayout.moved?(@home)
      raise Refused, "a delivery lock is held: #{held.join(", ")}" unless held.empty?
      raise Refused, "#{copy} exists; remove it or move it away first" if File.exist?(copy)
    end

    def held
      Dir.glob(LOCKS, base: @home).select { |lock| Time.now - File.mtime(File.join(@home, lock)) < Lock::TTL_SECONDS }
    end

    def moves
      @moves ||= GLOBAL_ENTRIES.select { |name| File.exist?(File.join(@home, name)) }.map { |name| [name, "stores/global/#{name}"] } +
        project_entries.map { |entry| ["projects/#{entry}", "stores/#{entry}"] }
    end

    def project_entries
      Dir.exist?(projects) ? Dir.children(projects).sort : []
    end

    def projects
      File.join(@home, "projects")
    end

    def rewrites
      [File.join(@home, "config.yml"), @qmd_index, *PATH_COLUMNS.keys.map { |name| File.join(@home, name) }].select { |file| File.file?(file) }
    end

    def run
      files = rewrites
      FileUtils.cp_r(@home, copy, preserve: true)
      moves.each { |from, to| move(from, to) }
      FileUtils.rmdir(projects) if Dir.exist?(projects)
      files.each { |file| PATH_COLUMNS.key?(File.basename(file)) ? rewrite_rows(file) : rewrite_text(file) }
    end

    def move(from, to)
      FileUtils.mkdir_p(File.dirname(File.join(@home, to)))
      FileUtils.mv(File.join(@home, from), File.join(@home, to))
    end

    def rewrite_text(file)
      FileUtils.cp(file, "#{file}.before-stores-move", preserve: true)
      File.write(file, [@home, "~/.plastic"].inject(File.read(file)) { |text, base| relocate(text, base) })
    end

    def relocate(text, base)
      text.gsub(%r{#{Regexp.escape(base)}/(store|roadmaps|INDEX\.md)\b}) { "#{base}/stores/global/#{Regexp.last_match(1)}" }
        .gsub(%r{#{Regexp.escape(base)}/projects\b}) { "#{base}/stores" }
    end

    def rewrite_rows(file)
      table, column = PATH_COLUMNS.fetch(File.basename(file))
      Sqlite.call(file, <<~SQL)
        UPDATE #{table} SET #{column} = 'stores/' || substr(#{column}, 10) WHERE #{column} LIKE 'projects/%';
        UPDATE #{table} SET #{column} = 'stores/global/' || #{column} WHERE #{column} LIKE 'store/%';
      SQL
    end
  end
end
