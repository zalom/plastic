# frozen_string_literal: true

require "fileutils"

# What the tests of two homes share. Home A makes the changes; home B holds A's printed files with no databases,
# under its own origin, and has read them once, so both homes hold rows. A pull copies A's files over B's, as
# version control does, and keeps B's databases.
module TwoHomesHelper
  IGNORED = Plastic::Graph::Knowledge::StoreFolder::IGNORED

  # Yields home A after `seed` made its first state and printed it, and home B after B read A's files once.
  def two_homes(seed: ->(_home) {})
    with_home do |a|
      seed.call(a)
      call_in(a, "store", "sync", "down")
      with_home do |b|
        pull(b, a)
        call_in(b, "store", "sync", "up")
        yield a, b
      end
    end
  end

  def store_of(home) = File.join(home, "stores", "global")

  def files_of(home)
    base = store_of(home)
    Dir.glob("**/*", File::FNM_DOTMATCH, base:).select { |rel| File.file?(File.join(base, rel)) && !ignored?(rel) }
  end

  def ignored?(rel) = IGNORED.any? { |pattern| File.fnmatch?(pattern, File.basename(rel)) }

  # The files of `from` replace the files of `to`, and a file `from` lacks is removed.
  def pull(to, from)
    theirs = files_of(from)
    (files_of(to) - theirs).each { |rel| File.delete(File.join(store_of(to), rel)) }
    theirs.each do |rel|
      target = File.join(store_of(to), rel)
      FileUtils.mkdir_p(File.dirname(target))
      FileUtils.cp(File.join(store_of(from), rel), target)
    end
  end

  def read_file(home, rel) = File.read(File.join(store_of(home), rel))

  def write_file(home, rel, text)
    path = File.join(store_of(home), rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, text)
  end

  def database_of(home) = home_graphs(home).databases.fetch(:store)

  def rows_of(home, sql, **values) = database_of(home).rows(sql, **values)

  def origin_of(home) = home_graphs(home).retrieval.origin_id

  def folder_of(home) = Plastic::Graph::Knowledge::StoreFolder.new(store_of(home))

  # Every file of the store folder with its bytes, to compare before and after a call.
  def files_snapshot(home) = files_of(home).sort.to_h { |rel| [rel, read_file(home, rel)] }
end
