# frozen_string_literal: true

require "digest"
require_relative "../../../support/child_process"
require "rbconfig"
require_relative "../../../test_helper"

class DbSchemaTest < Plastic::TestCase
  Schema = Plastic::Graph::Schema
  SchemaFile = Plastic::Graph::SchemaFile
  KERNEL = File.expand_path("../../../../lib", __dir__)
  SCHEMA_PATH = File.join(KERNEL, "plastic/graph/db/schema.rb")
  BUILDER_PATH = File.join(KERNEL, "plastic/graph/db/schema_file.rb")

  # The DDL of every table that existed before the schema file, pinned from origin/alpha.
  OLD_DDL = {
    sessions: "e1985f7782ebab6170830332214f9e453966fb2b6b5ce8d461e9b8733e3a316e",
    intents: "087d62f348bbab4a8c81a648f644b44dcccfbaf8d327f473eade388452429c4d",
    completions: "8c67722a7c53438b6a895b11684d87377fe8e8593215cc551bece619b3bdc60b",
    clusters: "4cf2401a09f74db26015897dd666449a6a172bba742884f39a2dd79447ad5987",
    nodes: "cfa14e4507a75f95cc241d0316046a819ab03b5fad0b179dbacbc2c53936dac8",
    edges: "32f8c35b13eefe9dc0ac2a13ddd61bbc8d31a276f188fc7039bb777d8c98be8a",
    documents: "b3bc6a8702f6306941d4d4431ae0f0e5ce00ff89c958a424513698865c2d481f",
    rulings: "b532c782f8edbf04043bf12e22054dd2f1d57f585dc7438b437f2d60d73e33f8",
    links: "1403ac943dc60477e4ad8e0dbd95027029fe8ae233064ca39a4a6540859e7c69",
    roadmaps: "c6cef5175e6cd02789ef8006f7280fca6ab9d89ed7c11a667c070a38cc988891",
    batches: "e44629686139e8f6c96cbabe4005b0d6e6bd62b0fae2dcd5603368adc03614ef",
    roadmap_items: "3eb970cd95cc301cf27fbce6f08ed6bcd4b62b0d3b4629e8861d271003dc6192",
    roadmap_edges: "295dfb63b0b77f8fc56e9894ce896c006c27aa9728b5683e2637cf1b276f7c1b",
    roadmap_log: "ed05eef89c9592b5b36da98a8cdd28009314de634a6663e56fc3fc73314ac3cd",
    archives: "1063eeec2b8c6c26d12bb3b369574b04a85a42c45093c5c945acc35f969f9070",
    archive_entries: "74ef9ff34717e62ae6a900425e78d716a3b96bb3dd62a0a36da57dd0896c7c8e",
    sqlar: "e009afa1c7e455192a87f15934d1082e9f304b49ceffeab8aece9948142713b1",
    printed: "eeb9e475e607f232e6c325c72d9de74debf78a53fa16b1bffd8839ba597c40be",
    document_heads: "b87ad04e374493805bac7cc34d9b53cb5293bcef0ec5303a4dafc439047c33b6",
    document_passages: "0c8ed03255aace08648603941623217e717b8a1942850c648e7289c3356adb57",
    retrieval_contexts: "6cf8985de162e5b6d0bb9518022145d4f1e29fded841fccc78e77886a03419d8",
    retrieval_discoveries: "c5007ca34c9bda2e98cca89774cc78f4547288623601395bd8997f4bc1e84491",
    document_fts: "cb79da3f2b5e36acc326b39310e72a0f4e33faa41eefa2940b986128654af325"
  }.freeze

  def test_every_table_that_existed_before_keeps_its_ddl
    assert_equal OLD_DDL, OLD_DDL.keys.to_h { |name| [name, Digest::SHA256.hexdigest(Schema.ddl(name))] }
  end

  def test_each_database_keeps_its_file_and_table_order
    assert_equal({
      local: ["plastic.db", %i[command_runs sessions settings printed chat_messages store_migrations]],
      work: ["work_graph.db", %i[nodes edges work_log roadmaps batches roadmap_items roadmap_edges roadmap_log runs]],
      knowledge: ["knowledge_graph.db", %i[intents clusters completions approvals verdicts archives archive_entries documents legacy_intents_data
        document_heads retrieval_contexts retrieval_discoveries
        rulings links printed sqlar]],
      retrieval: ["retrieval_graph.db", %i[document_passages document_fts]]
    }, Schema.databases)
  end

  def test_no_kernel_file_but_the_schema_file_declares_a_table
    allowed = [SCHEMA_PATH, BUILDER_PATH, File.join(KERNEL, "plastic/graph/table.rb")]
    files = Dir.glob(File.join(KERNEL, "**/*.rb")) - allowed

    refute_empty files
    assert_empty files.select { |path| File.read(path).match?(/\bcreate_table\b|\bDECLARED\b/) }
  end

  def test_an_unknown_column_type_raises_naming_it
    error = assert_raises(NoMethodError) do
      SchemaFile.define(version: 1) { create_table(:things, key: []) { |table| table.bogus :a } }
    end

    assert_includes error.message, "bogus"
  end

  def test_the_schema_file_loads_in_a_fresh_ruby
    out, err, status = ChildProcess.capture3(RbConfig.ruby, "-r", SCHEMA_PATH, "-e", "print Plastic::Graph::SCHEMA_FILE.version")

    assert_equal [true, "20261121090000", ""], [status.success?, out, err]
  end

  def test_the_schema_file_marks_legacy_intents_data_legacy
    assert_equal %i[intent_id path origin_id], Schema.table_named(:legacy_intents_data).key
  end

  def test_a_table_declares_its_key_columns_and_each_typed_column
    file = SchemaFile.define(version: 1) do
      create_table :things, key: %i[store intent_id] do |table|
        table.kept :store, :intent_id
        table.text :mode
        table.serial :id
      end
    end
    table = file.tables.fetch(:things)

    assert_equal %i[store intent_id], table.key
    assert_equal({ store: "TEXT NOT NULL", intent_id: "TEXT NOT NULL", mode: "TEXT", id: "INTEGER PRIMARY KEY AUTOINCREMENT" }, table.columns)
  end

  def test_a_table_with_no_key_declares_none
    file = SchemaFile.define(version: 1) { create_table(:things, key: []) { |table| table.serial :seq } }

    assert_empty file.tables.fetch(:things).key
  end

  def test_the_printed_table_is_not_counted_and_command_runs_are_counted
    assert_equal [false, true], [Schema.table_named(:printed).counted?, Schema.table_named(:command_runs).counted?]
  end

  def test_a_database_lists_tables_declared_once_and_shared
    assert_equal %i[local knowledge], %i[local work knowledge].select { |key| Schema.databases.fetch(key).last.include?(:printed) }
  end
end
