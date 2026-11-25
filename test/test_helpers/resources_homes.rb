# frozen_string_literal: true

require "digest"

# A store of the old layout: the files of one intent folder as agents left them, with the rows of the files a sync read.
module ResourcesHomes
  INTENT = "store/1--alpha"
  MOVES = {
    "reviews/r1.md" => "resources/tmp/reviews/r1.md",
    "resources/notes.md" => "resources/tmp/notes.md",
    "resources/data.csv" => "resources/output/files/data.csv",
    "references/ref.md" => "resources/references/ref.md",
    "review.rb" => "resources/tmp/review.rb",
    "runner-step.last" => "resources/tmp/runner-step.last"
  }.freeze
  OLD_FILES = {
    "spec.md" => "# Spec\n\nSee [review](reviews/r1.md) and [notes](resources/notes.md).\n",
    "reviews/r1.md" => "# Review\n\nBack to [the spec](../spec.md) and [ref](../references/ref.md).\n",
    "resources/notes.md" => "# Notes\n\n[web](https://example.com/a.md) [abs](/etc/hosts) [gone](missing.md) [data](data.csv#top)\n",
    "resources/data.csv" => "a,b\n",
    "references/ref.md" => "# Ref\n",
    "review.rb" => "puts 1\n",
    "runner-step.last" => "step\n",
    "plan.md" => "# Plan\n\n## Steps\n1. Do it.\n",
    "delivery.lock" => "pid\n"
  }.freeze
  HELD = %w[reviews/r1.md resources/notes.md references/ref.md].freeze

  def write_old_layout
    OLD_FILES.each { |rel, text| write("#{INTENT}/#{rel}", text) }
    HELD.each { |rel| hold_rows(rel, OLD_FILES.fetch(rel)) }
  end

  def hold_rows(rel, body)
    sha = Digest::SHA256.hexdigest(body)
    store_database.transaction do |batch|
      batch.put(:documents, { intent_id: "1", path: rel, body:, updated_at: Plastic::TestCase::STAMP })
      batch.put(:document_heads, { intent_id: "1", path: rel, sha256: sha, updated_at: Plastic::TestCase::STAMP })
      batch.put(:printed, { path: "#{INTENT}/#{rel}", sha256: sha, at: Plastic::TestCase::STAMP })
    end
  end

  def row_paths(table, column = "path") = store_database.rows("SELECT #{column} AS path FROM #{table} ORDER BY #{column}").map { |row| row.values.first }

  def intent_files = snapshot(File.join(store_root, INTENT)).keys

  def row_digest = %w[documents document_heads printed].to_h { |table| [table, store_database.rows("SELECT * FROM #{table} ORDER BY 1, 2").map(&:values)] }

  def relative_targets(text) = text.scan(/\]\(([^)\s]+)\)/).flatten.reject { |target| target.match?(%r{\A(?:[a-z]+:|/)}) }

  def files_without_databases = snapshot(store_root).reject { |rel, _| rel.match?(/\.db(-wal|-shm|-journal)?\z/) }

  def failing_on_the_third
    calls = 0
    lambda do |from, to|
      calls += 1
      raise Errno::EACCES, to if calls == 3

      File.rename(from, to)
    end
  end
end
