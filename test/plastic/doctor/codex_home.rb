# frozen_string_literal: true

require_relative "whole_home"
require_relative "../../../scripts/lib/plastic/hooks/entries"

module CodexHome
  include WholeHome

  def codex_dir = File.join(@home, ".codex")

  def codex_record = File.join(@home, ".agents", "plastic", "VERSION")

  def codex_hooks_path = File.join(codex_dir, "hooks.json")

  def codex_launcher = File.join(@plastic_home, "bin", "plastic")

  def whole_codex
    whole_home
    write(codex_record, "#{RUNNING}\n")
    write(File.join(codex_dir, "AGENTS.md"), "Read ~/.plastic/PLASTIC.md.\n")
    write(codex_launcher, "#!/bin/sh\n")
    File.chmod(0o755, codex_launcher)
    codex_hooks
  end

  def codex_hooks
    entries = Plastic::Hooks::Entries.new(command: codex_launcher, config: Plastic::Config.new(@plastic_home), launchers: {})
    write(codex_hooks_path, JSON.generate(entries.codex({})))
  end

  def change_codex_hook(event)
    data = JSON.parse(File.read(codex_hooks_path))
    yield data.fetch("hooks").fetch(event).first.fetch("hooks").first
    write(codex_hooks_path, JSON.generate(data))
  end
end
