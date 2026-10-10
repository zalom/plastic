# frozen_string_literal: true

require "rexml/document"

module ArchitectureFiguresHelper
  ROOT = File.expand_path("../..", __dir__)
  FIGURES = File.join(ROOT, "docs", "contributing", "figures")
  DOCUMENT = File.join(ROOT, "docs", "contributing", "ARCHITECTURE.md")

  def committed_figures = Dir[File.join(FIGURES, "*.svg")].to_h { |path| [File.basename(path), File.read(path)] }

  def texts(svg) = REXML::Document.new(svg).get_elements("//text").map { |node| [node.attributes["class"].to_s, node.texts.map(&:value).join] }

  def declared_names = ArchitectureFigures::FIGURES.flat_map(&:names)

  def drawn_texts = ArchitectureFigures.render.values.flat_map { |svg| texts(svg) }

  def whole_token?(label, text) = text.match?(/(?<![\w:.])#{Regexp.escape(label)}(?![\w:])/)

  def load_kernel
    require "plastic"
    require "plastic/graph"
    require "plastic/cli/table"
    require "plastic/workflows/registry"
    true
  end

  def class_exists?(ref)
    load_kernel
    require "plastic/#{Plastic::CLI.file_of(ref)}"
    ref.split("::").inject(Plastic) { |scope, part| scope.const_get(part, false) }
    true
  rescue NameError, LoadError
    false
  end

  CHECKS = {
    "class" => :class_check, "command" => :command_check, "workflow" => :workflow_check, "table" => :table_check,
    "database" => :database_check, "store_file" => :store_file_check, "path" => :path_check
  }.freeze

  def schema
    load_kernel
    Plastic::Graph::SCHEMA_FILE
  end

  def name_exists?(type, ref)
    check = CHECKS.fetch(type, :never)
    respond_to?(check, true) ? send(check, ref) : false
  end

  def never(_ref) = false
  def class_check(ref) = class_exists?(ref)
  def command_check(ref) = load_kernel && Plastic::CLI::TABLE.key?(ref)
  def workflow_check(ref) = load_kernel && Plastic::Workflows::REGISTRY.include?(ref.delete_prefix(":").to_sym)
  def table_check(ref) = (schema.tables.keys - schema.legacy).include?(ref.to_sym)
  def database_check(ref) = schema.databases.values.map(&:first).include?(ref)
  def store_file_check(ref) = Dir[File.join(ROOT, "scripts", "lib", "plastic", "**", "*.rb")].any? { |file| File.read(file).include?(ref) }
  def path_check(ref) = File.exist?(File.join(ROOT, ref))

  def missing_names(names) = names.reject { |type, _label, ref| name_exists?(type, ref) }
end
