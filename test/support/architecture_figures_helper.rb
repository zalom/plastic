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
  end

  def class_exists?(ref)
    load_kernel
    require "plastic/#{Plastic::CLI.file_of(ref)}"
    ref.split("::").inject(Plastic) { |scope, part| scope.const_get(part, false) }
    true
  rescue NameError, LoadError
    false
  end

  def schema
    load_kernel
    Plastic::Graph::SCHEMA_FILE
  end

  def name_exists?(type, ref)
    case type
    when "class" then class_exists?(ref)
    when "command" then load_kernel && Plastic::CLI::TABLE.key?(ref)
    when "workflow" then load_kernel && Plastic::Workflows::REGISTRY.key?(ref.delete_prefix(":").to_sym)
    when "table" then (schema.tables.keys - schema.legacy).include?(ref.to_sym)
    when "database" then schema.databases.values.map(&:first).include?(ref)
    when "store_file" then Dir[File.join(ROOT, "scripts", "lib", "plastic", "**", "*.rb")].any? { |file| File.read(file).include?(ref) }
    when "path" then File.exist?(File.join(ROOT, ref))
    else false
    end
  end

  def missing_names(names) = names.reject { |type, _label, ref| name_exists?(type, ref) }
end
