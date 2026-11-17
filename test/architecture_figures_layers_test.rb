# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/child_process"
require "rbconfig"

class ArchitectureFiguresLayersTest < Minitest::Test
  SHAPES = File.expand_path("../tools/architecture_figures/shapes", __dir__)

  def shape_files = Dir.glob(File.join(SHAPES, "*.rb"))

  def test_the_shapes_require_nothing_outside_their_folder
    outside = shape_files.flat_map { |file| File.read(file).scan(/require_relative "([^"]+)"/).flatten.map { |path| [File.basename(file), path] } }
      .reject { |_file, path| File.expand_path(path, SHAPES).start_with?("#{SHAPES}/") && !path.start_with?("..") }

    assert_empty outside
  end

  def test_every_shape_file_loads_alone
    failures = shape_files.filter_map do |file|
      _out, error, status = ChildProcess.capture3(RbConfig.ruby, "-e", "require 'cgi/escape'; require ARGV.first", file)
      "#{File.basename(file)}: #{error.lines.first&.strip}" unless status.success?
    end

    assert_empty failures
  end

  def test_the_shapes_entry_file_requires_every_shape_and_no_canvas
    entry = File.read(File.expand_path("../tools/architecture_figures/shapes.rb", __dir__))

    assert_equal shape_files.map { |file| File.basename(file, ".rb") }.sort, entry.scan(%r{require_relative "shapes/(\w+)"}).flatten.sort
    refute_includes entry, "canvas"
  end
end
