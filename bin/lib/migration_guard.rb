# frozen_string_literal: true

# Docs: docs/contributing/MIGRATIONS.md.
module MigrationGuard
  FOLDER = "lib/plastic/graph/db/migrate"
  NAME = %r{\A#{FOLDER}/(?<kind>[a-z]+)/(?<version>\d{14})_}

  # Each side maps a path to its bytes: the tip of the base branch, the head, and the merge base of the two.
  def self.check(base:, head:, merge_base: base)
    merged = base.keys
    added = (head.keys - merged).sort
    above = newest(merged)
    changed(base, head, merge_base) + added.filter_map { |path| too_early(path, above) } + shared(added)
  end

  def self.changed(base, head, merge_base)
    base.keys.reject { |path| head[path] == base.fetch(path) }.sort.map { |path| merged_problem(path, head, merge_base) }
  end

  def self.merged_problem(path, head, merge_base)
    return "#{path} was merged to the base after this branch was cut; rebase onto the base" unless head.key?(path) || merge_base.key?(path)

    "#{path} is a merged migration and was changed, renamed or deleted; add a new migration instead"
  end

  def self.newest(paths)
    versions = paths.filter_map { |path| NAME.match(path)&.values_at(:kind, :version) }
    versions.sort.to_h
  end

  def self.too_early(path, newest)
    found = NAME.match(path) or return
    kind, version = found.values_at(:kind, :version)
    above = newest[kind]
    return unless above && version <= above

    "#{path} has the version #{version}, which is not above #{above}, the newest #{kind} migration on the base branch; give it a later timestamp"
  end

  def self.shared(paths)
    versioned = paths.grep(NAME).group_by { |path| NAME.match(path).values_at(:kind, :version) }
    versioned.select { |_key, group| group.size > 1 }.map do |(kind, version), group|
      "#{group.join(" and ")} share the #{kind} version #{version}; give one a later timestamp"
    end
  end
  private_class_method :changed, :merged_problem, :newest, :too_early, :shared
end
