# frozen_string_literal: true

require "minitest/autorun"

# A method name says what the method does. `run` says nothing, and `take` hides
# whether it locks, captures or reads, so neither names a method. Names that
# start with `test_` are left out.
class MethodNamesGuardTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  FOLDERS = %w[lib bin tools scripts exe test].freeze
  DEFINITION = /^\s*def\s+(?:self\.)?([A-Za-z_]\w*[!?=]?)/
  RUN = /\Arun!?\z/
  TAKE = /\A(?:\w*_)?take(?:_\w*)?[!?=]?\z/
  SCOPE = /^(\s*)(?:class|module)\s/
  SCOPE_END = /^(\s*)end\s*$/
  METHOD = /^(\s*)def\s+(self\.)?([A-Za-z_]\w*[!?=]?)/

  def sources
    FOLDERS.flat_map { |folder| Dir[File.join(ROOT, folder, "**", "*")] }.select { |path| ruby_file?(path) }
  end

  def ruby_file?(path)
    File.file?(path) && (path.end_with?(".rb") || File.open(path, &:gets).to_s.match?(/\A#!.*ruby/))
  end

  def defined_names(text) = text.scan(DEFINITION).flatten.reject { |name| name.start_with?("test_") }

  def vague_names(text) = defined_names(text).grep(Regexp.union(RUN, TAKE))

  # Walks the lines with a stack of the bodies that are open; a definition belongs to the
  # innermost body when it sits one step deeper than that body's own line.
  def repeated_names(text)
    bodies = []
    text.each_line.filter_map { |line| track(bodies, line) }.uniq
  end

  def track(bodies, line)
    indent = line[/\A\s*/].size
    if line.match?(SCOPE)
      bodies.push({ indent:, seen: [] })
      nil
    elsif line.match?(SCOPE_END)
      bodies.pop if bodies.last && bodies.last[:indent] == indent
      nil
    else
      record(bodies.last, line, indent)
    end
  end

  def record(body, line, indent)
    found = line.match(METHOD)
    return unless body && found && indent == body[:indent] + 2

    key = "#{found[2]}#{found[3]}"
    (found[3] if body[:seen].include?(key)).tap { body[:seen] << key }
  end

  def test_the_sources_are_read_from_the_disk
    refute_empty sources
  end

  def test_the_detector_catches_run_and_take_methods
    sample = "class A\n  def run\n  end\n\n  def self.take_lock(id)\n  end\n  def run!(*args)\n  end\nend\n"

    assert_equal %w[run take_lock run!], vague_names(sample)
  end

  def test_the_detector_leaves_clear_names_and_test_names_alone
    sample = "class A\n  def run_report\n  end\n\n  def last_run\n  end\n  def test_take_the_lock\n  end\n  def retake\n  end\nend\n"

    assert_empty vague_names(sample)
  end

  def test_the_detector_catches_a_name_defined_twice_in_one_body
    sample = "class A\n  def read\n    1\n  end\n\n  def self.read\n  end\n\n  def read = 2\nend\n"

    assert_equal %w[read], repeated_names(sample)
  end

  def test_the_detector_leaves_the_same_name_in_two_bodies_alone
    sample = "module M\n  class A\n    def read = 1\n  end\n\n  class B\n    def read\n      2\n    end\n  end\n\n  def read = 3\nend\n"

    assert_empty repeated_names(sample)
  end

  def test_no_class_or_module_body_defines_one_name_twice
    offenders = sources.to_h { |path| [path.delete_prefix("#{ROOT}/"), repeated_names(File.read(path))] }.reject { |_, names| names.empty? }

    assert_empty offenders
  end

  def test_no_method_is_named_run_or_take
    offenders = sources.to_h { |path| [path.delete_prefix("#{ROOT}/"), vague_names(File.read(path))] }.reject { |_, names| names.empty? }

    assert_empty offenders
  end
end
