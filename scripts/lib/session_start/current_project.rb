# encoding: UTF-8

require "yaml"
require_relative "../store_layout"
require_relative "index_file"

module SessionStartHook
  # Which project (if any) the current working directory belongs to, and
  # that project's own active/future lines (intent 231: home and the store
  # are two different paths).
  module CurrentProject
    # A projects.yml entry whose path matched the current working directory.
    Match = Struct.new(:slug, :info, :project_path)

    def self.detect(plastic_home)
      projects_path = "#{plastic_home}/projects.yml"
      return nil unless File.exist?(projects_path)

      find_current(plastic_home, read_projects(projects_path))
    end

    def self.read_projects(projects_path)
      YAML.safe_load_file(projects_path)
    rescue
      {}
    end

    def self.find_current(plastic_home, projects)
      match = match_for(projects["projects"] || {}, Dir.pwd)
      match ? build(plastic_home, match) : nil
    end

    def self.match_for(projects, cwd)
      projects.each_pair do |slug, info|
        project_path = File.expand_path(info["path"])
        return Match.new(slug: slug, info: info, project_path: project_path) if cwd.start_with?(project_path)
      end
      nil
    end

    def self.build(plastic_home, match)
      slug = match.slug
      project_index = File.join(Plastic::StoreLayout.project_root(plastic_home, slug), "INDEX.md")
      active, future = File.exist?(project_index) ? IndexFile.parse(project_index) : [[], []]
      { "slug" => slug, "parent" => match.info["parent"], "path" => match.project_path,
        "active" => active, "future" => future }
    end
  end
end
