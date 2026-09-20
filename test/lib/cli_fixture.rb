# encoding: UTF-8
# frozen_string_literal: true

require "fileutils"
require "stringio"
require "yaml"

# CliFixture (intent 363) - a plastic home on disk for the command tests, plus
# the three injected seams every command takes: an output stream, an error
# stream and an environment. No test reads the real ~/.plastic or ~/.claude, so
# every path here is built under a temporary directory the caller owns.
class CliFixture
  attr_reader :home, :plastic_home, :out, :err

  def initialize(dir)
    @home = File.join(dir, "home")
    @plastic_home = File.join(@home, ".plastic")
    @out = StringIO.new
    @err = StringIO.new
    @projects = {}
    FileUtils.mkdir_p(@plastic_home)
  end

  def env(extra = {})
    { "PLASTIC_HOME" => @plastic_home }.merge(extra)
  end

  def streams
    { out: @out, err: @err, env: env, home: @home }
  end

  def printed
    @out.string
  end

  def warned
    @err.string
  end

  def global_store(active: [], completed: [])
    write_store(@plastic_home, active: active, completed: completed)
    self
  end

  def project(slug, active: [], completed: [], repository: nil)
    root = File.join(@plastic_home, "projects", slug)
    write_store(root, active: active, completed: completed)
    @projects[slug] = { "path" => repository || File.join(@home, "code", slug) }
    FileUtils.mkdir_p(@projects[slug]["path"])
    write_projects
    self
  end

  # A projects.yml row with no store behind it. Plastic registers a repository
  # before the first intent is written there, so this is an ordinary state, and
  # it is the one that reaches Scope#root's fallback. `info` takes whatever the
  # file might really hold, including a row that is not a mapping at all.
  def register(slug, info)
    @projects[slug] = info
    write_projects
    self
  end

  def roadmap(slug, name, body)
    root = slug == "global" ? @plastic_home : File.join(@plastic_home, "projects", slug)
    dir = File.join(root, "roadmaps")
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "#{name}.md"), body)
    self
  end

  def intent_dir(slug, id)
    root = slug == "global" ? @plastic_home : File.join(@plastic_home, "projects", slug)
    Dir.glob(File.join(root, "store", "#{id}--*")).first
  end

  def drop_index(slug)
    root = slug == "global" ? @plastic_home : File.join(@plastic_home, "projects", slug)
    FileUtils.rm_f(File.join(root, "INDEX.md"))
    self
  end

  private

  def write_projects
    File.write(File.join(@plastic_home, "projects.yml"), YAML.dump("projects" => @projects))
  end

  def write_store(root, active:, completed:)
    store = File.join(root, "store")
    FileUtils.mkdir_p(store)
    (active + completed).each do |id, title|
      dir = File.join(store, "#{id}--#{title.downcase.gsub(/[^a-z0-9]+/, "-")}")
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, "plan.md"), "# Plan for #{id}\n")
    end
    File.write(File.join(root, "INDEX.md"), index_body(active, completed))
  end

  def index_body(active, completed)
    lines = ["# Index", "", "## Active", ""]
    active.each { |id, title| lines << entry_line(id, title) }
    lines += ["", "## Completed", ""]
    completed.each { |id, title| lines << entry_line(id, title) }
    lines.join("\n") + "\n"
  end

  def entry_line(id, title)
    slug = title.downcase.gsub(/[^a-z0-9]+/, "-")
    "- [#{id} — #{title}](store/#{id}--#{slug}/#{id}--#{slug}.md)"
  end
end
