# frozen_string_literal: true

require "varar"
require "tmpdir"
require "yaml"
require_relative "support/public_command"

steps do
  sensor("the slug, the path, the exit and the registered slugs") do |_state, row|
    Dir.mktmpdir("varar-project-new") do |home|
      command = PublicCommand.new(home)
      repo = File.join(home, "repoa")
      FileUtils.mkdir_p(repo)
      File.write(File.join(repo, "AGENTS.md"), "# repoa\n")
      command.run("project", "new", "repoa", "--path", repo) if row.fetch("path") == "registered"
      code, = command.run("project", "new", row.fetch("slug"), "--path", repo)
      yml = File.join(home, ".plastic", "projects.yml")
      slugs = File.exist?(yml) ? YAML.safe_load_file(yml).fetch("projects", {}).keys : []
      row.merge("exit" => code.to_s, "registered slugs" => slugs.empty? ? "none" : slugs.sort.join(", "))
    end
  end
end
