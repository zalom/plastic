# frozen_string_literal: true

require_relative "test_helper"
require "command_reference"

# The pages of every command, built once for all the command reference tests.
module CommandReferenceHelper
  ROOT = File.expand_path("..", __dir__)

  def self.model = (@model ||= CommandReference::Model.new(ROOT))

  def self.pages = (@pages ||= Plastic::CLI::TABLE.keys.to_h { |words| [words, model.page(words)] })

  def self.build = (@build ||= CommandReference::Build.new(ROOT))

  def self.files = (@files ||= build.files)

  def page(words) = CommandReferenceHelper.pages.fetch(words)

  def exit_rows(words, code) = page(words).endings.select { |ending| ending.exit_code == code }

  def source_line(file, line) = File.readlines(File.join(CommandReferenceHelper::ROOT, file), chomp: true).fetch(line - 1)
end
