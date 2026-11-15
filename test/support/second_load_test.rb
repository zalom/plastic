# frozen_string_literal: true

require_relative "../test_helper"
require_relative "second_load"

class SecondLoadTest < Plastic::TestCase
  def source(text) = File.join(@home, "loaded.rb").tap { |path| File.write(path, text) }

  def test_a_block_that_answers_true_keeps
    assert SecondLoad.keeps?(source("1\n")) { true }
  end

  def test_a_block_that_answers_false_does_not_keep
    refute SecondLoad.keeps?(source("1\n")) { false }
  end

  def test_a_file_that_raises_on_load_does_not_keep
    refute SecondLoad.keeps?(source("raise 'broken'\n")) { true }
  end

  def test_the_load_leaves_the_test_process_untouched
    path = source("SecondLoadTest::LOADED = true\n")

    assert SecondLoad.keeps?(path) { defined?(SecondLoadTest::LOADED) }
    refute defined?(SecondLoadTest::LOADED)
  end
end
