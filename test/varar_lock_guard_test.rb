# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "varar/core/hash"

class VararLockGuardTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def documents = Dir.glob("varar/**/*.md", base: ROOT).sort

  def baselines = JSON.parse(File.read(File.join(ROOT, "varar.lock.json"))).fetch("oaths")

  def source_hash(path) = Varar::Core::Hash32.hash_source(File.read(File.join(ROOT, path)))

  def stale(paths, lock) = paths.reject { |path| lock.dig(path, "sourceHash") == source_hash(path) }

  def test_the_subjects_are_read_from_the_disk
    refute_empty documents
  end

  def test_the_stale_detector_catches_a_changed_hash_and_leaves_a_current_one_alone
    path = documents.first

    assert_equal [path], stale([path], { path => { "sourceHash" => "fnv1a:00000000" } })
    assert_empty stale([path], { path => { "sourceHash" => source_hash(path) } })
  end

  def test_every_varar_document_hash_matches_the_lock
    assert_empty stale(documents, baselines), "run VARAR_UPDATE=1 ruby bin/test --system and commit varar.lock.json"
  end

  def test_the_lock_names_only_existing_documents
    assert_empty baselines.keys - documents
  end
end
