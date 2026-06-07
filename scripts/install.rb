#!/usr/bin/env ruby
# encoding: UTF-8
# frozen_string_literal: true

# Plastic installer — runs via npx shim or directly.
# Usage: ruby scripts/install.rb [--claude] [--codex] [--hermes] [--all] [--uninstall] [--force] [--help]

require "json"
require "yaml"
require "fileutils"
require "digest"

PACKAGE_ROOT = ENV["PLASTIC_PACKAGE_ROOT"] || File.expand_path("..", __dir__)
PLASTIC_HOME = File.join(Dir.home, ".plastic")
VERSION = File.read(File.join(PACKAGE_ROOT, "package.json")).then { |s| JSON.parse(s)["version"] }

AGENTS = [
  { key: "claude", name: "Claude Code", dir: File.join(Dir.home, ".claude"), flag: "--claude" },
  { key: "codex", name: "Codex CLI", dir: File.join(Dir.home, ".agents"), flag: "--codex" },
  { key: "hermes", name: "Hermes", dir: File.join(Dir.home, ".hermes"), flag: "--hermes" },
].freeze

def main
  flags = parse_flags(ARGV)

  if flags[:help]
    show_help
    return
  end

  puts "\n\u{1f9e0} Plastic v#{VERSION}\n\n"

  if flags[:uninstall]
    handle_uninstall(flags[:agents].empty? ? ["claude"] : flags[:agents])
    return
  end

  agents = flags[:agents].empty? ? prompt_agents : flags[:agents]

  if agents.empty?
    puts "No agents selected. Nothing to do."
    return
  end

  mode = File.exist?(File.join(PLASTIC_HOME, "INDEX.md")) ? :update : :install
  puts "Mode: #{mode}"
  puts "Agents: #{agents.map { |k| agent_config(k)[:name] }.join(", ")}\n\n"

  distribute(mode)
  bootstrap if mode == :install

  results = agents.map { |key| install_for_agent(key, flags[:force]) }

  puts "\n\u{2014} Results \u{2014}\n\n"
  results.each do |r|
    if r[:success]
      puts "  \u{2705} #{r[:agent]}: #{r[:files]} files installed"
    else
      puts "  \u{26a0}\u{fe0f}  #{r[:agent]}: #{r[:reason]}"
    end
  end

  installed = results.select { |r| r[:success] }
  if installed.any?
    puts "\n\u{2705} Plastic v#{VERSION} #{mode == :update ? "updated" : "installed"}."
    puts "   Registered for: #{installed.map { |r| r[:agent] }.join(", ")}"
    puts "   Run /clear (or restart your agent) to pick up new conventions.\n\n"
  end
end

# --- Flag parsing ---

def parse_flags(argv)
  flags = { agents: [], force: false, uninstall: false, help: false }

  argv.each do |arg|
    case arg
    when "--all" then flags[:agents] = AGENTS.map { |a| a[:key] }
    when "--force" then flags[:force] = true
    when "--uninstall" then flags[:uninstall] = true
    when "--help", "-h" then flags[:help] = true
    else
      agent = AGENTS.find { |a| a[:flag] == arg }
      flags[:agents] << agent[:key] if agent
    end
  end

  flags
end

def prompt_agents
  unless $stdin.tty?
    return ["claude"]
  end

  puts "Which agents should Plastic register for?\n\n"
  AGENTS.each_with_index { |a, i| puts "  #{i + 1}. #{a[:name]} (#{a[:dir]})" }
  puts "  #{AGENTS.size + 1}. All"
  puts

  print "Select (comma-separated numbers, or Enter for Claude Code): "
  answer = $stdin.gets&.strip || ""

  return ["claude"] if answer.empty?

  nums = answer.split(",").map { |n| n.strip.to_i }
  return AGENTS.map { |a| a[:key] } if nums.include?(AGENTS.size + 1)

  nums.select { |n| n >= 1 && n <= AGENTS.size }.map { |n| AGENTS[n - 1][:key] }
end

def show_help
  puts <<~HELP

    plastic - Intent-driven idea development system

    Usage:
      npx @zalom/plastic@latest [options]

    Options:
      --claude      Install for Claude Code
      --codex       Install for Codex CLI
      --hermes      Install for Hermes
      --all         Install for all supported agents
      --force       Overwrite existing files without prompting
      --uninstall   Remove Plastic from agent directories
      -h, --help    Show this help

    Examples:
      npx @zalom/plastic@latest              Interactive agent selection
      npx @zalom/plastic@latest --claude     Install for Claude Code only
      npx @zalom/plastic@latest --all        Install for all agents
      npx @zalom/plastic@latest --uninstall  Remove from agent directories

  HELP
end

# --- Distribution phase ---

def distribute(mode)
  puts "  \u{1f4e6} #{mode == :update ? "Updating" : "Installing"} core files to #{PLASTIC_HOME}"

  FileUtils.mkdir_p(PLASTIC_HOME)
  FileUtils.mkdir_p(File.join(PLASTIC_HOME, "scripts"))

  core_files = {
    "PLASTIC.md" => "PLASTIC.md",
    "deprecations.yml" => "deprecations.yml",
    "scripts/folgezettel-id" => "scripts/folgezettel-id",
    "scripts/read-config" => "scripts/read-config",
  }

  core_files.each do |src, dest|
    src_path = File.join(PACKAGE_ROOT, src)
    dest_path = File.join(PLASTIC_HOME, dest)
    FileUtils.cp(src_path, dest_path) if File.exist?(src_path)
  end

  File.write(File.join(PLASTIC_HOME, "VERSION"), "#{VERSION}\n")

  Dir.glob(File.join(PLASTIC_HOME, "scripts", "*")).each { |f| FileUtils.chmod(0o755, f) }

  puts "  \u{2705} Core files synced (v#{VERSION})"
end

def bootstrap
  puts "  \u{1f331} First install \u{2014} bootstrapping store..."

  FileUtils.mkdir_p(File.join(PLASTIC_HOME, "store"))
  FileUtils.mkdir_p(File.join(PLASTIC_HOME, "projects"))

  write_if_missing(File.join(PLASTIC_HOME, "config.yml"), <<~YAML)
    version: 3
    execution_mode: subagent-driven
    stale_threshold_days: 3
    hash_length: 6
    hash_algorithm: sha256-base36
    max_slug_words: 5
    agent:
      type: claude-code
      parallel_mode: agent-teams
  YAML

  write_if_missing(File.join(PLASTIC_HOME, "projects.yml"), "---\nprojects: {}\n")

  write_if_missing(File.join(PLASTIC_HOME, "INDEX.md"), <<~MD)
    # Index

    ## Active

    ## Future

    ## Clusters

    ## Abandoned

    ## Completed
  MD

  write_if_missing(File.join(PLASTIC_HOME, "AGENTS.md"), <<~MD)
    # Plastic \u{2014} Agent Instructions

    Read `PLASTIC.md` in this directory. It contains all Plastic conventions.
    Follow it exactly. Never modify it \u{2014} it is overwritten on plugin updates.

    This file (`AGENTS.md`) is where project-specific rules live.

    ---
  MD

  puts "  \u{2705} Store bootstrapped"
end

# --- Agent adapters ---

def install_for_agent(key, force)
  config = agent_config(key)
  return { agent: config[:name], success: false, reason: "Unknown agent" } unless config

  unless File.directory?(config[:dir])
    return { agent: config[:name], success: false, reason: "#{config[:dir]} not found \u{2014} #{config[:name]} not installed?" }
  end

  case key
  when "claude" then install_claude(config, force)
  when "codex" then install_codex(config, force)
  when "hermes" then install_hermes(config, force)
  end
end

def install_claude(config, force)
  hooks_dir = File.join(config[:dir], "hooks")
  skills_dir = File.join(config[:dir], "skills", "plastic")
  plastic_dir = File.join(config[:dir], "plastic")

  FileUtils.mkdir_p(hooks_dir)
  FileUtils.mkdir_p(skills_dir)
  FileUtils.mkdir_p(plastic_dir)

  installed = []

  # Copy hooks
  hook_source = File.join(PACKAGE_ROOT, "hooks")
  Dir.glob(File.join(hook_source, "*")).each do |f|
    next unless File.file?(f)
    basename = File.basename(f)
    next if %w[hooks.json run-hook].include?(basename)
    dest_name = basename.start_with?("plastic-") ? basename : "plastic-#{basename}"
    dest = File.join(hooks_dir, dest_name)
    FileUtils.cp(f, dest)
    FileUtils.chmod(0o755, dest)
    installed << dest
  end

  # Copy skills recursively
  skills_source = File.join(PACKAGE_ROOT, "skills")
  installed += copy_dir_recursive(skills_source, skills_dir) if File.directory?(skills_source)

  # Write VERSION
  version_file = File.join(plastic_dir, "VERSION")
  File.write(version_file, "#{VERSION}\n")
  installed << version_file

  # Merge hooks into settings.json
  settings_path = File.join(config[:dir], "settings.json")
  merge_claude_hooks(settings_path)

  # Write manifest
  manifest_path = File.join(plastic_dir, "manifest.json")
  write_manifest(installed, manifest_path)

  { agent: config[:name], success: true, files: installed.size }
end

def install_codex(config, force)
  skills_dir = File.join(config[:dir], "skills", "plastic")
  FileUtils.mkdir_p(skills_dir)

  installed = []
  skills_source = File.join(PACKAGE_ROOT, "skills")
  installed += copy_dir_recursive(skills_source, skills_dir) if File.directory?(skills_source)

  manifest_path = File.join(config[:dir], "plastic-manifest.json")
  write_manifest(installed, manifest_path)

  { agent: config[:name], success: true, files: installed.size }
end

def install_hermes(config, force)
  skills_dir = File.join(config[:dir], "skills", "plastic")
  FileUtils.mkdir_p(skills_dir)

  installed = []
  skills_source = File.join(PACKAGE_ROOT, "skills")
  installed += copy_dir_recursive(skills_source, skills_dir) if File.directory?(skills_source)

  manifest_path = File.join(config[:dir], "plastic-manifest.json")
  write_manifest(installed, manifest_path)

  { agent: config[:name], success: true, files: installed.size }
end

# --- settings.json merge (read-modify-write, never clobber) ---

def merge_claude_hooks(settings_path)
  settings = read_json_safe(settings_path) || {}
  return if settings.nil? # unparseable — refuse to modify

  hooks = settings["hooks"] ||= {}
  hook_dir = File.join(Dir.home, ".claude", "hooks")

  plastic_hooks = {
    "SessionStart" => [
      { "type" => "command", "command" => "ruby #{hook_dir}/plastic-session-start", "statusMessage" => "Loading Plastic context..." },
      { "type" => "command", "command" => "#{hook_dir}/plastic-check-update", "statusMessage" => "" },
    ],
    "PreCompact" => [
      { "type" => "command", "command" => "ruby #{hook_dir}/plastic-savepoint", "statusMessage" => "Saving Plastic intent state..." },
    ],
    "PostToolUse" => [
      { "matcher" => "Write|Edit", "type" => "command", "command" => "#{hook_dir}/plastic-gate-check", "statusMessage" => "Checking lifecycle gates..." },
    ],
    "UserPromptSubmit" => [
      { "type" => "command", "command" => "#{hook_dir}/plastic-continue", "statusMessage" => "Checking for continue..." },
      { "type" => "command", "command" => "#{hook_dir}/plastic-future-intent-check", "statusMessage" => "Checking future intents..." },
    ],
    "statusLine" => [
      { "type" => "command", "command" => "#{hook_dir}/plastic-statusline" },
    ],
  }

  plastic_hooks.each do |event, entries|
    hooks[event] ||= []
    entries.each do |entry|
      already = hooks[event].any? { |h| h["command"] == entry["command"] }
      hooks[event] << entry unless already
    end
  end

  write_json_atomic(settings_path, settings)
end

# --- Uninstall ---

def handle_uninstall(agents)
  agents.each do |key|
    config = agent_config(key)
    next unless config

    result = uninstall_agent(key, config)
    if result[:success]
      puts "  \u{2705} #{config[:name]}: uninstalled (#{result[:files]} files removed)"
    else
      puts "  \u{26a0}\u{fe0f}  #{config[:name]}: #{result[:reason]}"
    end
  end

  puts "\n  Note: ~/.plastic/ (your intent store) is preserved.\n\n"
end

def uninstall_agent(key, config)
  unless File.directory?(config[:dir])
    return { success: false, reason: "#{config[:dir]} not found" }
  end

  manifest_path = case key
                  when "claude" then File.join(config[:dir], "plastic", "manifest.json")
                  else File.join(config[:dir], "plastic-manifest.json")
                  end

  files_removed = 0

  if File.exist?(manifest_path)
    manifest = JSON.parse(File.read(manifest_path)) rescue {}
    (manifest["files"] || {}).each_key do |f|
      if File.exist?(f)
        File.delete(f)
        files_removed += 1
      end
    end
    File.delete(manifest_path)
    files_removed += 1
  end

  # Clean known directories
  dirs_to_clean = case key
                  when "claude" then [File.join(config[:dir], "plastic"), File.join(config[:dir], "skills", "plastic")]
                  else [File.join(config[:dir], "skills", "plastic")]
                  end

  dirs_to_clean.each { |d| FileUtils.rm_rf(d) if File.directory?(d) }

  # Clean hooks from settings.json (Claude Code only)
  if key == "claude"
    settings_path = File.join(config[:dir], "settings.json")
    remove_claude_hooks(settings_path) if File.exist?(settings_path)
  end

  { success: true, files: files_removed }
end

def remove_claude_hooks(settings_path)
  settings = read_json_safe(settings_path)
  return unless settings && settings["hooks"]

  settings["hooks"].each do |event, entries|
    settings["hooks"][event] = entries.reject { |h| (h["command"] || "").include?("plastic-") }
  end
  settings["hooks"].delete_if { |_, v| v.empty? }
  settings.delete("hooks") if settings["hooks"]&.empty?

  write_json_atomic(settings_path, settings)
end

# --- Utilities ---

def agent_config(key)
  AGENTS.find { |a| a[:key] == key }
end

def copy_dir_recursive(src, dest)
  files = []
  FileUtils.mkdir_p(dest)
  Dir.entries(src).reject { |e| e.start_with?(".") }.each do |entry|
    src_path = File.join(src, entry)
    dest_path = File.join(dest, entry)
    if File.directory?(src_path)
      files += copy_dir_recursive(src_path, dest_path)
    elsif File.file?(src_path)
      FileUtils.cp(src_path, dest_path)
      files << dest_path
    end
  end
  files
end

def read_json_safe(path)
  return nil unless File.exist?(path)
  JSON.parse(File.read(path))
rescue JSON::ParserError
  # Try JSONC stripping (remove // comments and trailing commas)
  content = File.read(path).gsub(%r{//[^\n]*}, "").gsub(/,(\s*[}\]])/, '\1')
  JSON.parse(content)
rescue
  nil
end

def write_json_atomic(path, data)
  content = JSON.pretty_generate(data) + "\n"
  tmp = "#{path}.plastic-tmp.#{Process.pid}"
  File.write(tmp, content)
  File.rename(tmp, path)
rescue => e
  File.delete(tmp) if tmp && File.exist?(tmp)
  raise e
end

def write_manifest(files, manifest_path)
  entries = {}
  files.each do |f|
    entries[f] = Digest::SHA256.file(f).hexdigest if File.exist?(f)
  end

  data = { "version" => "1", "created" => Time.now.utc.iso8601, "files" => entries }
  File.write(manifest_path, JSON.pretty_generate(data) + "\n")
end

def write_if_missing(path, content)
  File.write(path, content) unless File.exist?(path)
end

# --- Run ---

main
