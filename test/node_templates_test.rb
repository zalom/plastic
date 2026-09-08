# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "yaml"
require_relative "../scripts/lib/node_file"
require_relative "../scripts/lib/graph_file"
require_relative "../scripts/lib/installer_core"

# Templates, one per kind (intent 334, n5). Flat filenames, never a
# templates/nodes/ subdirectory: InstallerCore#template_files does
# `next unless File.file?(path)`, so a subdirectory would reach no install
# at all - the intent 190 failure exactly.
class NodeTemplatesTest < Minitest::Test
  REPO = File.expand_path("../..", __dir__)
  TEMPLATES_DIR = File.join(REPO, "templates")

  KIND_TEMPLATES = {
    "work" => "node-work.md",
    "verify" => "node-verify.md",
    "decision" => "node-decision.md",
    "research" => "node-research.md",
  }.freeze

  def setup
    @dir = Dir.mktmpdir("node-templates")
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def template_path(basename)
    File.join(TEMPLATES_DIR, basename)
  end

  # --- one template per kind ---------------------------------------------------

  def test_one_template_per_kind
    KIND_TEMPLATES.each do |kind, basename|
      path = template_path(basename)
      assert File.exist?(path), "missing template for kind #{kind}: #{basename}"

      fm = File.read(path).split("---", 3)[1]
      data = YAML.safe_load(fm)
      assert_equal kind, data["kind"], "#{basename} must declare kind: #{kind}"
    end
  end

  # --- each template validates as its kind --------------------------------------

  def test_each_template_validates_as_its_kind
    KIND_TEMPLATES.each do |kind, basename|
      content = File.read(template_path(basename))
      id = content[/^node:\s*(\S+)/, 1]
      tmp_path = File.join(@dir, "#{id}.md")
      File.write(tmp_path, content)

      result = NodeFile.parse(tmp_path)
      assert result[:ok], "#{basename} (kind #{kind}) failed NodeFile.parse: #{result[:errors].inspect}"
    end
  end

  # --- the work template's matrix heading carries the id placeholder -----------

  def test_work_template_matrix_heading_carries_the_id
    content = File.read(template_path("node-work.md"))
    id = content[/^node:\s*(\S+)/, 1]
    tmp_path = File.join(@dir, "#{id}.md")
    File.write(tmp_path, content)

    result = NodeFile.parse(tmp_path)
    assert result[:ok], result[:errors].inspect

    sections = NodeFile.split_by_headings(result[:body])
    matrix = sections.find { |heading, _| heading.include?(id) && heading.match?(/matrix/i) }
    refute_nil matrix, "no heading in node-work.md carries the id #{id.inspect} and the word matrix"
    assert NodeFile.table_rows(matrix[1]).any?, "the id-bearing matrix heading owns no table row"
  end

  # --- the graph template's example graph parses, Status is rendered shape -----

  def test_graph_template_parses
    tmp_path = File.join(@dir, "graph.md")
    FileUtils.cp(template_path("graph.md"), tmp_path)

    result = GraphFile.parse(tmp_path)
    assert result[:ok], result[:errors].inspect

    rows = GraphFile.status_rows(tmp_path)
    refute_empty rows
    rendered = GraphFile.render_status_table(rows)
    assert_equal rendered.strip, result[:status].strip,
      "the template's ## Status must be the rendered shape a real write_status would produce, not hand-authored prose"
  end

  # --- reach an install: flat files, not a subdirectory -------------------------

  def test_templates_are_flat_files_the_installer_ships
    all_basenames = KIND_TEMPLATES.values + ["graph.md"]
    all_basenames.each do |basename|
      path = template_path(basename)
      assert File.file?(path), "#{basename} must be a flat file directly under templates/"
      assert_equal TEMPLATES_DIR, File.dirname(path)
    end

    installer = InstallerCore.new(package_root: REPO, plastic_home: @dir, version: "1.0.0-test")
    registered = installer.template_files.values
    all_basenames.each do |basename|
      assert_includes registered, File.join("templates", basename),
        "#{basename} missing from InstallerCore#template_files (the templates/* glob)"
    end
  end
end
