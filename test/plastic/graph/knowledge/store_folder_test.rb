# frozen_string_literal: true

require_relative "../../../test_helper"

class KnowledgeStoreFolderTest < Plastic::TestCase
  StoreFolder = Plastic::Graph::Knowledge::StoreFolder

  def setup
    super
    @root = File.join(@home, "folder")
    @folder = StoreFolder.new(@root)
  end

  def test_a_written_file_reads_back_with_its_digest
    @folder.write("store/1--a/spec.md", "# Spec\n")

    assert_equal [true, "# Spec\n", Digest::SHA256.hexdigest("# Spec\n")],
      [@folder.exist?("store/1--a/spec.md"), @folder.read("store/1--a/spec.md"), @folder.digest("store/1--a/spec.md")]
    assert_empty Dir.glob("#{@root}/**/*.tmp")
  end

  def test_a_missing_file_has_no_digest
    assert_nil @folder.digest("store/1--a/spec.md")
    refute @folder.exist?("store")
  end

  def test_a_deleted_file_is_gone
    @folder.write("INDEX.md", "x")
    @folder.delete("INDEX.md")

    refute_path_exists @folder.path("INDEX.md")
  end

  def test_a_store_is_legacy_only_with_index_md_and_no_index_json
    states = [[]] + [%w[INDEX.md], %w[store/index.json]].map do |files|
      files.each { |rel| @folder.write(rel, "x") }
      @folder.legacy?
    end

    assert_equal [[], true, false], states
  end

  def test_intent_files_list_every_kept_file_of_every_intent_folder
    %w[store/1--a/spec.md store/1--a/.hidden store/1--a/delivery.lock store/1--a/.DS_Store store/2--b/x/y.bin
      store/notes.md].each { |rel| @folder.write(rel, "x") }

    assert_equal %w[store/1--a store/2--b], @folder.intent_dirs
    assert_equal %w[store/1--a/.hidden store/1--a/spec.md store/2--b/x/y.bin], @folder.intent_files
  end

  def test_the_databases_are_ignored_once_beside_the_lines_already_there
    @folder.write(".gitignore", "notes/\n*.db\n")
    2.times { @folder.ignore_databases }

    assert_equal "notes/\n*.db\n*.db-journal\n", @folder.read(".gitignore")
  end

  def test_content_lock_files_are_kept
    @folder.write("store/1--a/Gemfile.lock", "dependency versions")

    assert_includes @folder.intent_files, "store/1--a/Gemfile.lock"
  end

  def test_a_new_ignore_file_lists_both_patterns
    @folder.ignore_databases

    assert_equal "*.db\n*.db-journal\n", @folder.read(".gitignore")
  end

  def test_the_context_file_of_an_intent_folder_is_a_generated_view
    assert Plastic::Graph::Knowledge::StoreFolder.graph_view?("store/1--alpha/context.json")
    refute Plastic::Graph::Knowledge::StoreFolder.graph_view?("store/1--alpha/notes.json")
  end
end
