# frozen_string_literal: true

require "json"
require_relative "../test_helper"
require_relative "../../lib/plastic/installations"

# A harness folder, its settings file and a record, for the tests of Installations::Removal.
module RemovalFixture
  PLASTIC = "plastic hook start"
  MINE = "my-start"
  SECTION = "<!-- BEGIN PLASTIC COMPACT hash:abc -->\nbody\n<!-- END PLASTIC COMPACT -->\n"

  def folder = File.join(@home, ".claude")

  def settings_path = File.join(folder, "settings.json")

  def write(path, text)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, text)
    path
  end

  def record(**parts)
    Plastic::Installations::Record.new(harness: "claude-code", version: "2.0.5", roots: [folder], files: [], folders: [],
      settings: settings_path, hooks: [], status_line: nil, permissions: [], sections: [], **parts)
  end

  def removed(record)
    Plastic::Installations.write(@plastic_home, record)
    Plastic::Installations::Removal.new(record, plastic_home: @plastic_home).call
  end

  def settings = JSON.parse(File.read(settings_path))

  def hook(command) = { "hooks" => [{ "type" => "command", "command" => command }] }

  def section_for(path) = { "file" => path, "begin" => "<!-- BEGIN PLASTIC COMPACT", "end" => "<!-- END PLASTIC COMPACT -->" }
end
