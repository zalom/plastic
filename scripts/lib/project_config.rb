# encoding: UTF-8
# frozen_string_literal: true

require "yaml"

# ProjectConfig - reads a project's project.yml merged over the shipped defaults
# (moved off the retired shared-helpers module by intent 344, D2). A missing or
# malformed project.yml never raises: read returns the defaults with a warning
# on stderr instead.
module ProjectConfig
  module_function

  DEFAULTS = {
    "governing_docs" => ["AGENTS.md"],
    "release" => {
      "on_complete" => "commit",
    },
  }.freeze

  def read(slug)
    path = File.join(Dir.home, ".plastic", "projects", slug, "project.yml")
    config = if File.exist?(path)
               YAML.safe_load(File.read(path)) || {}
             else
               {}
             end

    deep_merge(DEFAULTS, config)
  rescue => e
    $stderr.puts "Warning: failed to read project config for #{slug}: #{e.message}"
    DEFAULTS.dup
  end

  def deep_merge(base, overlay)
    result = base.dup
    overlay.each do |key, value|
      if value.is_a?(Hash) && result[key].is_a?(Hash)
        result[key] = deep_merge(result[key], value)
      else
        result[key] = value
      end
    end
    result
  end
end
