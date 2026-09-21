# frozen_string_literal: true

require "yaml"
require "date"
require_relative "../command"
require_relative "../legacy"
require_relative "../../store_provisioning"

# `plastic project new` - registers a project in projects.yml, then provisions
# and validates its store (`provision-project-store`, `validate-project`, run
# through Legacy). The project directory must already exist; this command
# never makes one, and a slug already registered is a Failure.
module Plastic
  class CLI
    module Commands
      class ProjectNew < Command
        USAGE_LINE = "plastic project new SLUG --path PATH [--parent ID] [--json]"

        def initialize(argv, runner: nil, **streams)
          super(argv, **streams)
          @runner = runner
        end

        def call
          raise Usage, "SLUG is required" if slug.to_s.empty?
          raise Usage, "--path is required" if options[:path].to_s.empty?
          raise Failure, "#{options[:path]} does not exist" unless Dir.exist?(options[:path])
          raise Failure, "#{slug} is already registered" if StoreProvisioning.registered?(slug, scope.plastic_home)

          register
          run("provision-project-store", slug, "--home", scope.plastic_home)
          run("validate-project", slug, "--home", scope.plastic_home)
          @output.next_step("plastic project links", because: "the new store's Links section needs projecting before anything cites it")
        end

        private

        def slug
          arguments.first
        end

        def switches(parser)
          parser.on("--path PATH") { |v| @options[:path] = v }
          parser.on("--parent ID") { |v| @options[:parent] = v }
        end

        def projects_yml
          File.join(scope.plastic_home, "projects.yml")
        end

        def register
          data = File.exist?(projects_yml) ? (YAML.safe_load_file(projects_yml) || {}) : {}
          data["projects"] ||= {}
          entry = {"path" => File.expand_path(options[:path]), "registered" => Date.today.to_s, "status" => "active"}
          entry["parent"] = options[:parent] if options[:parent]
          data["projects"][slug] = entry
          File.write(projects_yml, YAML.dump(data))
        end

        def run(script, *args)
          status = legacy.run(script, *args)
          raise Failure, "#{script} exited #{status}" unless status.zero?
        end

        def legacy
          @legacy ||= Legacy.new(env: @env, runner: @runner)
        end
      end
    end
  end
end
