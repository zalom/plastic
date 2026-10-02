# frozen_string_literal: true

require "digest"
require "fileutils"
require "tmpdir"
require_relative "../config"
require_relative "roadmap_parse"

module Plastic
  module Graph
    # Imports every legacy store under a home: `Sync::LegacyImport` for the
    # intent files, then the rulings, links, roadmaps, kept originals and
    # roadmaps and kept originals the legacy import does not do on its own.
    # Nothing is removed during the import. Only after a store imports with
    # no error, and only when migrate.remove_after_import is on, INDEX.md is
    # removed and the folders of done and abandoned intents are archived.
    # `:dry_run` runs the same import against a throwaway copy of the home;
    # `:apply` runs it against the home it is given.
    class MigrateWriter
      StoreReport = Data.define(:store, :skipped, :counts, :problems)

      TOKEN = /\A[A-Za-z0-9][A-Za-z0-9_-]*\z/.freeze
      RULING_ID = /\A\*{0,2}D(\d+)\b/.freeze
      DONE_STATES = %w[done abandoned].freeze

      def initialize(home, mode:, session: nil)
        @home = home
        @mode = mode
        @session = session
      end

      def call
        (@mode == :dry_run) ? dry_run : import(@home)
      end

      private

      def dry_run
        Dir.mktmpdir do |copy|
          FileUtils.cp_r(Dir.glob(File.join(@home, "*")), copy)
          import(copy)
        end
      end

      def import(home) = store_dirs(home).map { |dir| migrate_store(home, File.basename(dir)) }

      def store_dirs(home) = Dir.glob(File.join(home, "stores", "*")).select { |path| File.directory?(path) }.sort

      def migrate_store(home, slug)
        folder = StoreFolder.new(File.join(home, "stores", slug))
        folder.legacy? ? imported_report(home, slug, folder) : leftover_report(home, slug, folder)
      end

      def report(slug, counts: {}, problems: [], skipped: false) = StoreReport.new(store: slug, skipped:, counts:, problems:)

      def imported_report(home, slug, folder)
        root = folder.root
        parsed = roadmap_files(root).to_h { |path| [path, RoadmapParse.call(File.read(path, encoding: "UTF-8"), path: relative(root, path))] }
        problems = parsed.values.flat_map(&:problems)
        return report(slug, problems:) if problems.any?

        counts = rolled_back_on_error(root) { run_import(home, slug, root, folder, parsed) }
      rescue => e
        report(slug, problems: ["#{slug}: the import failed and the store was put back: #{e.message}"])
      else
        removed_after_import(home, slug, folder, counts)
      end

      # A store imported on an earlier run that still holds INDEX.md: removed
      # now when the flag has been turned on since, skipped otherwise.
      def leftover_report(home, slug, folder)
        return report(slug, skipped: true) unless remove_after_import? && folder.exist?(StoreFolder::LEGACY_INDEX)

        removed_after_import(home, slug, folder, Hash.new(0))
      end

      def remove_after_import? = Config.new(@home).flag(%w[migrate remove_after_import], default: false)

      # Runs only after the store imported with no error. A failure here keeps
      # the rows already written and says what was left in place.
      def removed_after_import(home, slug, folder, counts)
        return report(slug, counts:) unless remove_after_import?

        graphs = Graph.open(home:, store: slug, session: @session)
        archive_done_intents(graphs.work, graphs.retrieval, counts)
        folder.delete(StoreFolder::LEGACY_INDEX)
        report(slug, counts:)
      rescue => e
        report(slug, counts:, problems: ["#{slug}: imported, but removing the imported files stopped: #{e.message}"])
      end

      # A store that fails halfway gets its folder back as it was, databases
      # gone, so the next run imports it again instead of skipping it.
      def rolled_back_on_error(root)
        Dir.mktmpdir do |saved|
          FileUtils.cp_r(root, saved)
          yield
        rescue
          FileUtils.rm_rf(root)
          FileUtils.cp_r(File.join(saved, File.basename(root)), File.dirname(root))
          raise
        end
      end

      def relative(root, path) = path.delete_prefix("#{root}/")

      def roadmap_files(root) = Dir.glob(File.join(root, "roadmaps", "{,archived/}*.md")).reject { |path| path.end_with?(".savepoint.md") }.sort

      def run_import(home, slug, root, folder, parsed)
        originals = folder.intent_files.to_h { |path| [path, folder.read(path)] }
        decisions = read_decisions(folder.intent_dirs, originals)
        graphs = Graph.open(home:, store: slug, session: @session)
        counts = Hash.new(0)
        graphs.work.sync_apply(graphs.work.sync_plan(:up, {}))
        tally_sync(counts, graphs.retrieval)
        write_decisions(graphs.databases, decisions, counts)
        keep_changed_originals(graphs.databases, folder, originals, counts)
        migrate_roadmaps(graphs, root, parsed, counts)
        counts
      end

      def tally_sync(counts, retrieval)
        counts[:intents] = retrieval.intents.size
        counts[:documents] = retrieval.documents.size
        counts[:savepoints] = retrieval.savepoints.size
      end

      # Rulings and links read from the ORIGINAL bytes, before the sync runs:
      # the legacy import does not keep sources, chain or Decisions. When
      # spec.md lists decisions, it holds them and the intent file's copy is
      # skipped, since both files carry the same decisions in other words.
      def read_decisions(dirs, originals)
        dirs.map do |dir|
          main, spec = ["#{File.basename(dir)}.md", "spec.md"].map { |name| text_of(originals["#{dir}/#{name}"]) }
          bullets = [spec, main].map { |text| decision_bullets(text) }.find(&:any?) || []
          { intent_id: File.basename(dir).split("--").first, rulings: assign_ruling_ids(bullets),
            source: front_matter_refs(main, "sources"), chain: front_matter_refs(main, "chain") }
        end
      end

      def text_of(bytes) = bytes.to_s.dup.force_encoding(Encoding::UTF_8)

      def write_decisions(databases, decisions, counts)
        decisions.each do |decision|
          intent_id = decision.fetch(:intent_id)
          write_rulings(databases, intent_id, decision.fetch(:rulings), counts)
          %i[source chain].each { |kind| write_links(databases, intent_id, decision.fetch(kind), kind.to_s, counts) }
        end
      end

      def decision_bullets(text)
        bullets = []
        level = nil
        text.each_line do |raw|
          line = raw.chomp
          heading = line.match(/\A(#+)\s+(.+)\z/)
          if heading
            level = nil if level && heading[1].length <= level
            level = heading[1].length if heading[2].strip == "Decisions"
          elsif level && line.strip.start_with?("- ")
            bullets << line.strip.delete_prefix("- ").strip
          end
        end
        bullets
      end

      # A bullet that opens with Dn keeps that id unless an earlier bullet
      # took it; every other bullet takes the next free number.
      def assign_ruling_ids(bullets)
        taken = []
        bullets.map do |bullet|
          number = bullet[RULING_ID, 1].to_i
          number = (taken.max || 0) + 1 if number.zero? || taken.include?(number)
          taken << number
          ["D#{number}", bullet]
        end
      end

      def write_rulings(databases, intent_id, bullets, counts)
        database = databases.fetch(:knowledge)
        bullets.each do |id, text|
          row = { intent_id:, id:, text:, supersedes: nil, at: Plastic.now, session_id: @session }
          database.transaction { |batch| batch.put(:rulings, row, statement: :insert) }
          counts[:rulings] += 1
        end
      end

      def front_matter_refs(text, key)
        line = text[/^#{Regexp.escape(key)}:\s*(\[.*\])\s*$/, 1]
        line ? line.scan(/"([^"]+)"/).flatten : []
      end

      def write_links(databases, intent_id, refs, kind, counts)
        database = databases.fetch(:knowledge)
        refs.each do |ref|
          row = { from_ref: intent_id, to_ref: ref, kind:, at: Plastic.now }
          database.transaction { |batch| batch.put(:links, row, statement: :insert) }
          counts[:links] += 1
        end
      end

      def keep_changed_originals(databases, folder, originals, counts)
        originals.each do |path, before|
          after = folder.exist?(path) ? folder.read(path) : nil
          next if after == before

          intent_id = path.sub(%r{\Astore/}, "").split("/").first.split("--").first
          keep_original(databases, path, before, intent_id, counts)
        end
      end

      def keep_original(databases, path, bytes, intent_id, counts)
        row = { name: "originals/#{path}", mode: 0o644, mtime: Time.now.to_i, sz: bytes.bytesize,
                data: SQL::Bytes.new(bytes), intent_id:, sha256: Digest::SHA256.hexdigest(bytes) }
        databases.fetch(:references).transaction { |batch| batch.put(:sqlar, row, statement: :upsert) }
        counts[:kept] += 1
      end

      def migrate_roadmaps(graphs, root, parsed, counts)
        parsed.each do |path, result|
          slug = File.basename(path, ".md")
          original_bytes = File.binread(path)
          write_roadmap_rows(graphs, slug, result, path.sub(/\.md\z/, ".savepoint.md"))
          graphs.work.print_roadmap(slug)
          keep_roadmap_original(graphs.databases, root, slug, original_bytes, counts)
          counts[:roadmaps] += 1
          counts[:roadmap_items] += result.items.size
        end
      end

      # A roadmap with no batch headings lists its items in one batch.
      def write_roadmap_rows(graphs, slug, result, savepoint)
        databases = graphs.databases
        work = graphs.work
        fields = ->(title) { RoadmapWriter::Fields.new(title:, goal: nil, done: []) }
        batches = result.batches.empty? ? [RoadmapParse::Batch.new(position: 1, title: result.title)] : result.batches
        batches.each { |batch| work.write_batch(slug, batch.position, fields: fields.call(batch.title)) }
        result.items.each { |item| add_item(graphs, slug, item, fields.call(item.title)) }
        write_edges(databases, slug, result.edges)
        write_log(databases, slug, result.log + savepoint_log(savepoint))
        databases.fetch(:work).transaction { |batch| batch.put(:roadmaps, { slug:, title: result.title, goal: result.goal }, statement: :upsert) }
      end

      # An imported item keys by its intent id, so it names that intent when the store holds one.
      def add_item(graphs, slug, item, fields)
        id = item.item
        graphs.work.add_item(slug, id, item.batch || 1, fields:, after: [])
        graphs.work.start_item(slug, id, id) if graphs.retrieval.intent(id)
      end

      # The `.savepoint.md` sibling: one line per event, its time stamp first.
      def savepoint_log(path)
        return [] unless File.exist?(path)

        File.read(path, encoding: "UTF-8").each_line.filter_map do |line|
          at, text = line.strip.split(/\s+/, 2)
          RoadmapParse::LogLine.new(at:, text: text.to_s.squeeze(" ")) if at
        end
      end

      def write_edges(databases, slug, edges)
        database = databases.fetch(:work)
        edges.each do |to, froms|
          froms.each { |from| database.transaction { |batch| batch.put(:roadmap_edges, { roadmap: slug, from:, to:, kind: "after" }, statement: :insert) } }
        end
      end

      def write_log(databases, slug, log)
        database = databases.fetch(:work)
        log.each_with_index do |line, index|
          row = { roadmap: slug, position: index + 1, at: line.at, text: line.text, session_id: @session }
          database.transaction { |batch| batch.put(:roadmap_log, row, statement: :insert) }
        end
      end

      def keep_roadmap_original(databases, root, slug, original_bytes, counts)
        canonical = File.join(root, "roadmaps", "#{slug}.md")
        after = File.exist?(canonical) ? File.binread(canonical) : nil
        return if after == original_bytes

        keep_original(databases, "roadmaps/#{slug}.md", original_bytes, nil, counts)
      end

      def archive_done_intents(work, retrieval, counts)
        retrieval.intents.each do |intent|
          next unless DONE_STATES.include?(intent.status)

          ok, = work.archive_intent(intent.intent_id)
          counts[:archived] += 1 if ok
        end
      end
    end
  end
end
