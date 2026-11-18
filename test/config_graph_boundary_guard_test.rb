# frozen_string_literal: true

require_relative "test_helper"

class ConfigGraphBoundaryGuardTest < Minitest::Test
  LIB = File.expand_path("../lib/plastic", __dir__)

  def files(folder, file) = [File.join(LIB, file), *Dir.glob(File.join(LIB, folder, "**", "*.rb"))]

  def naming(folder, file, pattern)
    files(folder, file).select { |path| File.read(path, encoding: "UTF-8").match?(pattern) }.map { |path| path.delete_prefix("#{LIB}/") }
  end

  def test_both_folders_are_read_from_the_disk
    refute_empty files("config", "config.rb")
    refute_empty files("graph", "graph.rb")
  end

  def test_no_config_file_names_graph
    assert_empty naming("config", "config.rb", /\bGraph\b|graph\//)
  end

  def test_no_graph_file_names_config
    assert_empty naming("graph", "graph.rb", /\bConfig\b|config"/)
  end
end
