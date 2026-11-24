# frozen_string_literal: true

require_relative "change"
require_relative "removal"
require_relative "revisions"
require_relative "../../knowledge/resources/sort_plan"
require_relative "../../../errors"

module Plastic
  module Graph
    module Knowledge
      module Repair
        # What a repair of the intent folders of one store folder would do, read from the folder: the files that move or are
        # renamed where the layout names, the links that follow them, the files it removes, the entries of each old
        # revisions.md, and the `amended` lines. It writes nothing. The scope names the folders of `dirs`, every folder when
        # it is nil, never the folders of `held`, and the ids of the done and abandoned intents in `closed`. A closed intent
        # gets one amended line for each change; each revision entry is an amended line of any intent.
        class Plan
          Scope = Data.define(:dirs, :closed, :held) do
            def initialize(dirs: nil, closed: Set.new, held: Set.new) = super
          end

          UNREADABLE = "holds no revision entry the repair can read, or other text before its first one; " \
                       "fix the file by hand, then run plastic intent repair again"

          def initialize(folder, reports: nil, zone: nil, **scope)
            @folder = folder
            @reports = reports
            @zone = zone
            @scope = Scope.new(**scope)
          end

          def moves = sort.moves

          def rewrites = sort.rewrites

          def removals = (@removals ||= legacy_files("remove").map { |path| Removal.new(path) })

          # The old revisions.md files, each removed once its entries are amended lines.
          def revision_files = (@revision_files ||= legacy_files("amend"))

          # One amended line for each entry of each revisions.md, with its own time; refused when a file cannot be read.
          def revisions = (@revisions ||= revision_files.flat_map { |path| revision_lines(path) })

          def amendments = [*closed_changes, *revisions, *sort.amendments]

          def empty? = moves.empty? && removals.empty? && revision_files.empty?

          def preview
            [*moves.map { |move| move_preview(move) }, *removals.map(&:preview), *revision_files.map { |path| "preview: remove #{path}" },
              *sort.changed.map { |link| "preview: link would change #{link}" }, *amendments.map(&:preview),
              *sort.unresolved.map { |link| "preview: link left as it is #{link}" }]
          end

          # The lines a repair that moved `count` files prints.
          def report(count)
            ["repaired: #{count} files moved, #{removals.size + revision_files.size} removed", *sort.unasked,
              *sort.changed.map { |link| "link changed #{link}" }, *amendments.map(&:line), *sort.unresolved.map { |link| "link left as it is #{link}" }]
          end

          private

          def sort
            @sort ||= Resources::SortPlan.new(@folder, reports: @reports, closed: @scope.closed, only: @scope.dirs, held: @scope.held)
          end

          def dirs = (@dirs ||= (@scope.dirs || @folder.intent_dirs) - @scope.held.to_a)

          def legacy_files(repair) = dirs.flat_map { |dir| files(dir).select { |rel| Layout.legacy_for(rel)&.repair == repair }.map { |rel| "#{dir}/#{rel}" } }

          def files(dir) = Dir.glob("**/*", File::FNM_DOTMATCH, base: @folder.path(dir)).select { |rel| @folder.exist?("#{dir}/#{rel}") }.sort

          def closed?(dir) = @scope.closed.include?(SyncSelection.intent_of(dir))

          def renamed?(move) = Layout.legacy_for(move.inside_from)&.repair == "rename"

          def move_preview(move) = renamed?(move) ? "preview: rename #{move.from} -> #{move.to}" : sort.preview(move)

          def closed_changes = [*moves.filter_map { |move| moved_change(move) }, *removals.filter_map { |removal| removed_change(removal) }]

          def moved_change(move)
            dir = move.from.delete_suffix("/#{move.inside_from}")
            return unless closed?(dir)

            kind = renamed?(move) ? :rename : :move
            Change.of(kind, dir, "#{kind}d #{move.inside_from} to #{move.inside_to}", move.inside_to)
          end

          def removed_change(removal) = (Change.of(:remove, removal.dir, "removed #{removal.inside}", removal.inside) if closed?(removal.dir))

          def revision_lines(path)
            parsed = Revisions.new(@folder.read(path).force_encoding(Encoding::UTF_8), zone: @zone)
            raise Refused, "#{path} #{UNREADABLE}" unless parsed.readable?

            dir = File.dirname(path)
            name = File.basename(path)
            parsed.entries.map { |entry| Change.of(:revision, dir, "#{name} #{entry.label}: #{entry.text}", name, at: entry.at) }
          end
        end
      end
    end
  end
end
