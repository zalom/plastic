# frozen_string_literal: true

require "digest"
require "fileutils"
require "tmpdir"
require_relative "roadmap_parse"

module Plastic
  module Graph
    # Imports every legacy store under a home: `Sync::LegacyImport` for the
    # intent files, then the rulings, links, roadmaps, kept originals and
    # archive-after-import that the legacy import does not do on its own.
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
        root = File.join(home, "stores", slug)
        folder = StoreFolder.new(root)
        return StoreReport.new(store: slug, skipped: true, counts: {}, problems: []) unless folder.legacy?

        parsed = roadmap_files(root).to_h { |path| [path, RoadmapParse.call(File.binread(path), path: relative(root, path))] }
        problems = parsed.values.flat_map(&:problems)
        return StoreReport.new(store: slug, skipped: false, counts: {}, problems:) if problems.any?

        StoreReport.new(store: slug, skipped: false, counts: run_import(home, slug, root, folder, parsed), problems: [])
      end

      def relative(root, path) = path.delete_prefix("#{root}/")

      def roadmap_files(root) = (Dir.glob(File.join(root, "roadmaps", "*.md")) + Dir.glob(File.join(root, "roadmaps", "archived", "*.md"))).sort

      def run_import(home, slug, root, folder, parsed)
        originals = folder.intent_files.to_h { |path| [path, folder.read(path)] }
        dirs = folder.intent_dirs
        graphs = Graph.open(home:, store: slug, session: @session)
        counts = Hash.new(0)
        graphs.work.sync_apply(graphs.work.sync_plan(:up, {}))
        tally_sync(counts, graphs.retrieval)
        extract_rulings_and_links(graphs.databases, dirs, originals, counts)
        keep_changed_originals(graphs.databases, folder, originals, counts)
        migrate_roadmaps(graphs.databases, graphs.work, root, parsed, counts)
        archive_done_intents(graphs.work, graphs.retrieval, counts)
        counts
      end

      def tally_sync(counts, retrieval)
        counts[:intents] = retrieval.intents.size
        counts[:documents] = retrieval.documents.size
        counts[:savepoints] = retrieval.savepoints.size
      end

      # Rulings and links read from the ORIGINAL bytes, taken before the sync
      # ran: the legacy import does not keep sources, chain or Decisions.
      def extract_rulings_and_links(databases, dirs, originals, counts)
        dirs.each do |dir|
          intent_id = File.basename(dir).split("--").first
          main = "#{dir}/#{File.basename(dir)}.md"
          texts = [originals[main], originals["#{dir}/spec.md"]].compact
          write_rulings(databases, intent_id, texts.flat_map { |text| decision_bullets(text) }, counts)
          next unless originals[main]

          write_links(databases, intent_id, front_matter_refs(originals[main], "sources"), "source", counts)
          write_links(databases, intent_id, front_matter_refs(originals[main], "chain"), "chain", counts)
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

      def assign_ruling_ids(bullets)
        highest = 0
        bullets.map do |bullet|
          match = bullet.match(RULING_ID)
          id = match ? "D#{match[1]}" : "D#{highest + 1}"
          highest = [highest, id[1..].to_i].max
          [id, bullet]
        end
      end

      def write_rulings(databases, intent_id, bullets, counts)
        return if bullets.empty?

        database = databases.fetch(:knowledge)
        assign_ruling_ids(bullets).each do |id, text|
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
                data: bytes, intent_id:, sha256: Digest::SHA256.hexdigest(bytes) }
        databases.fetch(:references).transaction { |batch| batch.put(:sqlar, row, statement: :upsert) }
        counts[:kept] += 1
      end

      def migrate_roadmaps(databases, work, root, parsed, counts)
        parsed.each do |path, result|
          slug = File.basename(path, ".md")
          original_bytes = File.binread(path)
          write_roadmap_rows(databases, work, slug, result)
          work.print_roadmap(slug)
          keep_roadmap_original(databases, root, slug, original_bytes, counts)
          counts[:roadmaps] += 1
          counts[:roadmap_items] += result.items.size
        end
      end

      def write_roadmap_rows(databases, work, slug, result)
        fields = ->(title) { RoadmapWriter::Fields.new(title:, goal: nil, done: []) }
        result.batches.each { |batch| work.write_batch(slug, batch.position, fields: fields.call(batch.title)) }
        result.items.each { |item| work.add_item(slug, item.item, item.batch, fields: fields.call(item.title), after: []) }
        write_edges(databases, slug, result.edges)
        write_log(databases, slug, result.log)
        databases.fetch(:work).transaction { |batch| batch.put(:roadmaps, { slug:, title: result.title, goal: result.goal }, statement: :upsert) }
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
