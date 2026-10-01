# encoding: UTF-8

require_relative "../store_layout"

module SessionStartHook
  # The project (or global) banner with its active intent, the one piece of
  # intent context a live boot still carries (intent 341, G8, D4).
  module ProjectBanner
    def self.render(plastic_home:, project:, global_active:)
      project ? scoped(plastic_home, project) : global(global_active)
    end

    def self.scoped(plastic_home, project)
      slug = project["slug"]
      store = File.join(Plastic::StoreLayout.project_root(plastic_home, slug), "store").sub(Dir.home, "~")
      "Project: #{slug} | Store: #{store}/" + active_intent_suffix(project["active"])
    end

    def self.global(global_active)
      "PLASTIC — Global store loaded from ~/.plastic/" + active_intent_suffix(global_active)
    end

    def self.active_intent_suffix(active_lines)
      return "" unless active_lines.any? && active_lines.first =~ /\[([^\]]+)\].*store\/([\w-]+)\//

      intent_name, dir_name = $1, $2
      intent_id = dir_name.split("--").first
      "\nActive: [#{intent_id} — #{intent_name}] | Artifacts → store/#{dir_name}/"
    end
  end
end
