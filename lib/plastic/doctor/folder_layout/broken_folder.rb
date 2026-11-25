# frozen_string_literal: true

require_relative "../check"
require_relative "../../graph/knowledge/repair/plan"
require_relative "../../graph/knowledge/repair/revisions"

module Plastic
  module Doctor
    class FolderLayout
      # One intent folder that breaks the layout, read from the repair plan: the files outside the layout, the retired
      # files, and its old revisions.md. A revisions.md the repair cannot read is a finding of its own, left to a person.
      BrokenFolder = Data.define(:dir, :outside, :retired, :revisions, :unreadable) do
        # The rows of the folder, as findings of `layout`.
        def checks(layout)
          label = "layout #{layout.slug} #{File.basename(dir)}:"
          [(layout.finding(label, problems.join("; ")) unless problems.empty?), unreadable_check(label)].compact
        end

        private

        def problems
          [("outside the layout: #{outside.sort.join(", ")}" unless outside.empty?), ("retired: #{retired.sort.join(", ")}" unless retired.empty?),
            ("revisions.md holds entries that belong in the work log" if revisions)].compact
        end

        def unreadable_check(label)
          return unless unreadable

          Check.finding(label, "#{unreadable} #{Graph::Knowledge::Repair::Plan::UNREADABLE}", "fix #{unreadable} by hand, then run plastic doctor again")
        end
      end

      # The intent folders of a repair plan that break the layout, each as a BrokenFolder, in the order of their names.
      class BrokenFolders
        def initialize(plan, folder)
          @plan = plan
          @folder = folder
        end

        def to_a = (outside.keys | retired.keys | revisions.keys).sort.map { |dir| broken(dir) }

        private

        def broken(dir) = BrokenFolder.new(dir:, outside: outside.fetch(dir, []), retired: retired.fetch(dir, []), **revision(dir))

        def outside = (@outside ||= @plan.moves.group_by { |move| move.from.delete_suffix("/#{move.inside_from}") }.transform_values { |moves| moves.map(&:inside_from) })

        def retired = (@retired ||= @plan.removals.group_by(&:dir).transform_values { |removals| removals.map(&:inside) })

        def revisions = (@revisions ||= @plan.revision_files.to_h { |path| [File.dirname(path), path] })

        # The revisions.md of the folder, under :revisions when the repair can read it and under :unreadable when not.
        def revision(dir)
          path = revisions[dir]
          readable = path.nil? || Graph::Knowledge::Repair::Revisions.new(@folder.read(path).force_encoding(Encoding::UTF_8)).readable?
          readable ? { revisions: path, unreadable: nil } : { revisions: nil, unreadable: path }
        end
      end
    end
  end
end
