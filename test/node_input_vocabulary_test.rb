# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "tmpdir"

# Intent 338a (n5, D14): the word this rename retires must not survive outside
# the compatibility reader, its test, and the legacy fixture ledgers. This
# scan copies test/vocabulary_scan_test.rb's shape (SCANNED_PATHS, git
# ls-files, an offenders(root, files) class method returning "path:line"
# strings with "path:0" for a file-name hit, whole-segment matching) over the
# retired word instead. The retired word is built from parts everywhere in
# this file so the scan file itself carries no whole-word hit.
class NodeInputVocabularyTest < Minitest::Test
  REPO = File.expand_path("..", __dir__)

  WORD = "pack" + "et"

  # Snake/kebab: case-insensitive, the retired word or its plural, bounded on
  # both sides by a non-letter (start, end, underscore, hyphen, digit, dot,
  # space, or any other non-letter).
  SNAKE_KEBAB = /(?<![a-zA-Z])#{WORD}s?(?![a-zA-Z])/i
  # CamelCase: case-sensitive, the capitalized retired word or its plural, not
  # followed by a lowercase letter.
  CAMEL = /#{WORD.capitalize}s?(?![a-z])/
  REFUSED = Regexp.union(SNAKE_KEBAB, CAMEL)

  SCANNED_PATHS = %w[scripts hooks agents skills templates bin test docs PLASTIC.md].freeze

  # The only places allowed to spell the retired word out: the compatibility
  # reader, its own test, and the legacy fixture ledgers this rename never
  # touches.
  COMPATIBILITY_READER = %w[
    scripts/lib/node_input_compatibility.rb
    test/node_input_compatibility_test.rb
  ].freeze
  LEGACY_FIXTURES = "test/fixtures/ledgers/"

  def self.permitted?(rel)
    COMPATIBILITY_READER.include?(rel) || rel.start_with?(LEGACY_FIXTURES)
  end

  def self.offenders(root, files)
    hits = []
    files.each do |rel|
      hits << "#{rel}:0" if rel.match?(REFUSED)
      path = File.join(root, rel)
      next unless File.file?(path)
      raw = File.binread(path)
      text = raw.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
      text.each_line.with_index(1) do |line, n|
        next unless line.match?(REFUSED)
        hits << "#{rel}:#{n}"
      end
    end
    hits
  end

  def test_retired_word_lives_only_in_the_compatibility_reader
    scoped_files = tracked_files.reject { |rel| self.class.permitted?(rel) }
    offenders = self.class.offenders(REPO, scoped_files)
    assert_empty offenders,
      "retired word survives outside the compatibility reader (#{offenders.size}):\n#{offenders.first(30).join("\n")}"

    reader_offenders = self.class.offenders(REPO, ["scripts/lib/node_input_compatibility.rb"])
    refute_empty reader_offenders,
      "the compatibility reader must actually carry the retired word, or the permitted path is not real"
  end

  def test_scan_fails_on_planted_occurrences
    Dir.mktmpdir("node-input-vocabulary-planted") do |dir|
      snake_hit = "node_" + WORD
      kebab_hit = "node-" + WORD
      camel_hit = "Node" + WORD.capitalize
      name_hit_file = "review_" + WORD + "_test.rb"

      File.write(File.join(dir, "snake.rb"), "value = #{snake_hit}\n")
      File.write(File.join(dir, "kebab.md"), "the #{kebab_hit} flag\n")
      File.write(File.join(dir, "camel.rb"), "class #{camel_hit}; end\n")
      File.write(File.join(dir, name_hit_file), "nothing retired in the content\n")

      names = %w[snake.rb kebab.md camel.rb] + [name_hit_file]
      offenders = self.class.offenders(dir, names)

      assert_includes offenders, "snake.rb:1"
      assert_includes offenders, "kebab.md:1"
      assert_includes offenders, "camel.rb:1"
      assert_includes offenders, "#{name_hit_file}:0"
    end
  end

  def test_permitted_paths_are_the_reader_its_test_and_legacy_fixtures
    assert_equal %w[scripts/lib/node_input_compatibility.rb test/node_input_compatibility_test.rb],
      self.class::COMPATIBILITY_READER
    assert_equal "test/fixtures/ledgers/", self.class::LEGACY_FIXTURES

    refute self.class.permitted?("scripts/lib/node_input.rb")
    refute self.class.permitted?("test/fixtures/dogfood_intent/actions/ACTION_1.md")
    assert self.class.permitted?("scripts/lib/node_input_compatibility.rb")
    assert self.class.permitted?("test/node_input_compatibility_test.rb")
    assert self.class.permitted?("test/fixtures/ledgers/example.md")
  end

  def test_offenders_are_reported_with_path_and_line
    Dir.mktmpdir("node-input-vocabulary-format") do |dir|
      hit = "node_" + WORD
      File.write(File.join(dir, "a.md"), "clean line\n#{hit}\n")
      File.write(File.join(dir, "b.md"), "#{hit}\nclean line\n")

      offenders = self.class.offenders(dir, %w[a.md b.md])
      assert_equal %w[a.md:2 b.md:1], offenders.sort
    end
  end

  def test_scan_file_carries_no_hit_of_its_own
    offenders = self.class.offenders(REPO, ["test/node_input_vocabulary_test.rb"])
    assert_empty offenders
  end

  private

  def tracked_files
    out, _err, status = Open3.capture3("git", "-C", REPO, "ls-files", *SCANNED_PATHS)
    raise "git ls-files failed" unless status.success?
    out.lines.map(&:chomp).reject(&:empty?)
  end
end
