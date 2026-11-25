# frozen_string_literal: true

require_relative "change"
require_relative "folder_changes"
require_relative "missing_files"
require_relative "removal"
require_relative "rebuild/folders"
require_relative "revisions"
require_relative "totals"
require_relative "../../knowledge/resources/sort_plan"
require_relative "../../../errors"

module Plastic
  module Graph
    module Knowledge
      module Repair
        # What a repair of the intent folders of one store folder would do, read from the folder: the files that move or are
        # renamed where the layout names, the links that follow them, the files it removes, the entries of each old
        # revisions.md, the `amended` lines, and the files the layout requires of a closed intent that its folder lacks. It
        # writes nothing. The scope names the folders of `dirs`, every folder when it is nil, never the folders of `held`,
        # the ids of the done and abandoned intents in `closed`, and their statuses by id in `states`. A closed intent gets
        # one amended line for the structural changes of its folder and one for each link it changes; each revision entry
        # is an amended line of any intent. An empty .gitkeep placeholder is removed, not moved. The links left as they
        # are print only as a count unless `links_left` asks for each one.
        class Plan
          Scope = Data.define(:dirs, :closed, :held, :states, :ruled) do
            def initialize(dirs: nil, closed: Set.new, held: Set.new, states: {}, ruled: ->(_id) { "" }) = super
          end

          PLACEHOLDER = ".gitkeep"
          UNREADABLE = "holds no revision entry the repair can read, or other text before its first one; " \
                       "fix the file by hand, then run plastic intent repair again"

          def initialize(folder, reports: nil, zone: nil, links_left: false, **scope)
            @folder = folder
            @reports = reports
            @zone = zone
            @links_left = links_left
            @scope = Scope.new(**scope)
          end

          def moves = (@moves ||= sort.moves.reject { |move| placeholder?(move) })

          def rewrites = sort.rewrites

          # The old files the layout removes, and each empty placeholder.
          def removals = (@removals ||= [*legacy_files("remove"), *rebuilding.paths, *placeholders].sort.map { |path| Removal.new(path) })

          # The old revisions.md files, each removed once its entries are amended lines.
          # The old intent folders whose plan, checklist and action files give records.
          def rebuilds = rebuilding.intents

          # The intent folders the repair works on.
          def repaired_dirs = dirs

          def revision_files = (@revision_files ||= legacy_files("amend"))

          # One amended line for each entry of each revisions.md, with its own time; refused when a file cannot be read.
          def revisions = (@revisions ||= revision_files.flat_map { |path| revision_lines(path) })

          def amendments = (@amendments ||= [*folders.select { |folder| closed?(folder.dir) }.map(&:change), *noted])

          def empty? = moves.empty? && removals.empty? && revision_files.empty?

          # The files a closed intent of the scope lacks; a file a move of the repair brings counts as there.
          def missing = (@missing ||= MissingFiles.new(@folder, @scope.states, dirs:, arriving: moves.map(&:to)))

          # One line for each intent folder it changes, each link it changes, each other amended line and each thing it
          # lists, then its totals.
          def preview
            [*folders.map { |folder| folder_line(folder, "preview: would amend", "preview: would repair") },
              *rebuilds.map { |rebuild| "preview: would rebuild #{rebuild.dir}: #{rebuild.summary}" },
              *sort.changed.map { |link| "preview: link would change #{link}" }, *noted.map(&:preview),
              *listed.map { |line| "preview: #{line}" }, *summary("preview: ")]
          end

          # The lines a repair prints: its totals, then the lines of the preview as done.
          def report
            [*summary("repaired: "), *folders.map { |folder| folder_line(folder, "amended", "repaired") }, *sort.unasked,
              *rebuilds.map { |rebuild| "rebuilt #{rebuild.dir}: #{rebuild.summary}" },
              *sort.changed.map { |link| "link changed #{link}" }, *noted.map(&:line), *listed]
          end

          private

          # What the repair leaves as it is and lists: the links it cannot follow, when asked, and the files a closed intent
          # lacks.
          def listed = [*left.map { |link| "link left as it is #{link}" }, *missing.lines]

          # The totals line, or none when the repair changes nothing and leaves no link.
          def summary(prefix) = (empty? && sort.unresolved.empty?) ? [] : ["#{prefix}#{totals}"]

          def sort
            @sort ||= Resources::SortPlan.new(@folder, reports: @reports, closed: @scope.closed, only: @scope.dirs, held: @scope.held)
          end

          def rebuilding = (@rebuilding ||= Rebuild::Folders.new(@folder, legacy_files("rebuild"), states: @scope.states, ruled: @scope.ruled))

          def dirs = (@dirs ||= (@scope.dirs || @folder.intent_dirs) - @scope.held.to_a)

          def legacy_files(repair) = dirs.flat_map { |dir| files(dir).select { |rel| Layout.legacy_for(rel)&.repair == repair }.map { |rel| "#{dir}/#{rel}" } }

          def files(dir) = Dir.glob("**/*", File::FNM_DOTMATCH, base: @folder.path(dir)).select { |rel| @folder.exist?("#{dir}/#{rel}") }.sort

          def closed?(dir) = @scope.closed.include?(SyncSelection.intent_of(dir))

          def renamed?(move) = Layout.legacy_for(move.inside_from)&.repair == "rename"

          def placeholders = sort.moves.select { |move| placeholder?(move) }.map(&:from)

          def placeholder?(move) = File.basename(move.from) == PLACEHOLDER && @folder.read(move.from).empty?

          # The amended lines of the revision entries and of the links that change.
          def noted = [*revisions, *sort.amendments]

          def left = @links_left ? sort.unresolved : []

          def totals = Totals.new(folders:, links_changed: sort.changed.size, amended: amendments.size, links_left: sort.unresolved.size, listed: @links_left)

          def folder_line(folder, closed, open) = "#{closed?(folder.dir) ? closed : open} #{folder.dir}: #{folder.text}"

          # The structural changes of each intent folder the repair changes.
          def folders = (@folders ||= [*moves.map(&:dir), *gone.map(&:dir)].uniq.sort.map { |dir| folder(dir) })

          def folder(dir)
            renamed, moved = moves.select { |move| move.dir == dir }.partition { |move| renamed?(move) }
            rebuilt, removed = gone_in(dir)
            FolderChanges.new(dir, renamed:, moved:, removed:, rebuilt:)
          end

          # The files the repair removes from one folder: first the rebuilt ones, then the others.
          def gone_in(dir)
            rebuilt, removed = gone.select { |removal| removal.dir == dir }.partition { |removal| rebuilding.paths.include?(removal.path) }
            [rebuilt, removed].map { |removals| removals.map(&:inside) }
          end

          # Every file the repair removes: the old files, the placeholders and each revisions.md.
          def gone = [*removals, *revision_files.map { |path| Removal.new(path) }]

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
