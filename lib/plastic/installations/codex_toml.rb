# frozen_string_literal: true

require "yaml"
require_relative "../config/agent_models"
require_relative "files"
require_relative "role_text"

module Plastic
  module Installations
    # Renders one role file as a Codex agent document: a fixed field order, so
    # a second render is byte-identical to the first.
    module CodexToml
      CONTROL = /[\x00-\x08\x0b\x0c\x0e-\x1f]/

      module_function

      def render(source, override, effort_override, workers = nil)
        front, body = split(RoleText.fill(File.read(source), workers))
        name = front["name"] || File.basename(source, ".md")
        front = front.merge("name" => name.to_s)
        fields = model_fields(model_for(front, override), effort: effort_for(front, effort_override))
        "#{[heading(front), fields, instructions(body)].reject(&:empty?).join("\n")}\n"
      end

      def write(root, source, override, effort_override, workers = nil)
        target = File.join(root, "#{File.basename(source, ".md")}.toml")
        Files.write_text(target, render(source, override, effort_override, workers))
        target
      end

      def heading(front)
        %(name = "#{inline(front["name"])}"\ndescription = "#{inline(front["description"].to_s)}")
      end

      def instructions(body) = %(developer_instructions = """\n#{multiline(body.strip)}\n""")

      def model_for(front, override)
        return override unless override.to_s.empty?

        Config::AgentModels.shipped_model_for(front["name"], harness: "codex") || front["model"]
      end

      def effort_for(front, override)
        return override unless override.to_s.empty?

        front["effort"] || Config::AgentModels.shipped_effort_for(front["name"])
      end

      # [frontmatter, body]. A file with no frontmatter, or frontmatter that is
      # not a mapping, has an empty frontmatter.
      def split(content)
        match = content.match(/\A---\s*\n(.*?)\n---\s*\n?(.*)\z/m)
        return [{}, content] unless match

        front = begin
          YAML.safe_load(match[1])
        rescue Psych::Exception
          {}
        end
        [front.is_a?(Hash) ? front : {}, match[2]]
      end

      # A tier alias (opus, sonnet, haiku) names the Codex model of that tier
      # and its effort. Any other value is a Codex model id.
      def model_fields(model, effort: Config::AgentModels::DEFAULT_EFFORT)
        return "" if model.to_s.empty?

        lines = [%(model = "#{inline(named(model))}")]
        lines << %(model_reasoning_effort = "#{inline(effort)}") unless effort.to_s.empty?
        lines.compact.join("\n")
      end

      def named(model) = Config::AgentModels.effort_for(model) ? Config::AgentModels.codex_model_for(model).to_s : model.to_s

      def multiline(text) = escaped(text.to_s.gsub(/\r\n?/, "\n"))

      def inline(text) = escaped(text.to_s.gsub(/\s*\r?\n\s*/, " ").strip)

      def escaped(text)
        text.gsub("\\") { "\\\\" }.gsub('"') { '\\"' }.gsub(CONTROL) { |char| format('\u%04X', char.ord) }
      end
    end
  end
end
