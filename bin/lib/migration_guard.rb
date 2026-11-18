# frozen_string_literal: true

# Checks the migration files of a change against the tip of its base branch. A merged migration has run on homes
# and stores already, so it never changes; a new one must sort after every merged migration of its kind, or a
# database that recorded the later one would skip it. A pure function over the files and their bytes at each side.
# Docs: docs/contributing/MIGRATIONS.md.
module MigrationGuard
  FOLDER = "lib/plastic/graph/db/migrate"
  NAME = %r{\A#{FOLDER}/(?<kind>[a-z]+)/(?<version>\d{14})_}

  # The problems found, one line each; none means the change passes. Each side maps a path to its bytes.
  def self.check(base:, head:)
    merged = base.keys
    changed = merged.reject { |path| head[path] == base.fetch(path) }
    above = newest(merged)
    early = (head.keys - merged).sort.filter_map { |path| too_early(path, above) }
    changed.sort.map { |path| "#{path} is a merged migration and was changed, renamed or deleted; add a new migration instead" } + early
  end

  # The newest version of each kind among the paths.
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
  private_class_method :newest, :too_early
end
