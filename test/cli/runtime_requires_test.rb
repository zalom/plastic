# encoding: UTF-8
# frozen_string_literal: true

require_relative "../test_helper"
require "open3"
require_relative "../../scripts/lib/cli"

class CliRuntimeRequiresTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  DEMOTED_ON_RUBY_FOUR = %w[logger ostruct benchmark pstore].freeze

  def self.command_files
    Plastic::CLI::TABLE.each_value.map { |file, _const, _summary| File.join(ROOT, "scripts", "lib", "cli", "#{file}.rb") }
  end

  def requires_script(paths)
    paths.map { |path| "require #{path.inspect}" }.join("\n")
  end

  def test_the_dispatcher_loads_with_rubygems_off
    _out, err, status = Open3.capture3("ruby", "--disable-gems", "-e",
                                       requires_script([File.join(ROOT, "scripts", "lib", "cli.rb")]))

    assert_predicate status, :success?, err
  end

  def test_every_command_file_loads_with_rubygems_off
    self.class.command_files.each do |path|
      _out, err, status = Open3.capture3("ruby", "--disable-gems", "-e", requires_script([path]))

      assert_predicate status, :success?, "#{File.basename(path)}: #{err}"
    end
  end

  def test_every_command_file_loads_when_they_are_all_required_together
    _out, err, status = Open3.capture3("ruby", "--disable-gems", "-e",
                                       requires_script(self.class.command_files))

    assert_predicate status, :success?, err
  end

  def test_nothing_the_commands_load_names_rubygems
    script = requires_script(self.class.command_files) +
             "\nputs $LOADED_FEATURES.grep(/rubygems/).length"
    out, err, status = Open3.capture3("ruby", "--disable-gems", "-e", script)

    assert_predicate status, :success?, err
    assert_equal "0", out.strip
  end

  def test_no_command_reaches_a_library_ruby_four_demoted_from_the_default_set
    script = requires_script(self.class.command_files) +
             "\nputs $LOADED_FEATURES.grep(/#{DEMOTED_ON_RUBY_FOUR.join("|")}/).length"
    out, err, status = Open3.capture3("ruby", "--disable-gems", "-e", script)

    assert_predicate status, :success?, err
    assert_equal "0", out.strip
  end

  def test_the_doctor_boot_path_loads_with_rubygems_off
    _out, err, status = Open3.capture3("ruby", "--disable-gems", "-e",
                                       requires_script([File.join(ROOT, "scripts", "lib", "doctor_core.rb")]))

    assert_predicate status, :success?, err
  end

  def test_the_preflight_checks_load_with_rubygems_off
    _out, err, status = Open3.capture3("ruby", "--disable-gems", "-e",
                                       requires_script([File.join(ROOT, "scripts", "lib", "preflight.rb")]))

    assert_predicate status, :success?, err
  end
end
