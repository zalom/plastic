# frozen_string_literal: true

module InstallerRelease
  # The paths an activation writes outside the release: the core files in
  # the Plastic home, the agent files and blocks Plastic manages, and the
  # launcher. Stores and databases are never among them.
  class ManagedHome
    CORE = "{bin,scripts,templates,hooks,docs,VERSION,*.md,*.yml,*.yaml,*.json}"
    AGENT = %w[.claude/settings.json .claude/CLAUDE.md .codex/hooks.json .codex/AGENTS.md
      .claude/plastic .agents/plastic .hermes/plastic .claude/{hooks,skills,agents}/plastic-*
      .agents/skills/plastic-* .codex/agents/plastic-* .hermes/{skills,agents}/plastic-*].freeze

    def initialize(plastic_home:, user_home:, launcher:)
      @plastic_home = plastic_home
      @user_home = user_home
      @launcher = launcher
    end

    attr_reader :plastic_home, :user_home, :launcher

    def paths = [*Dir.glob(CORE, base: plastic_home).map { |name| File.join(plastic_home, name) }, *agent_paths, launcher]

    private

    def agent_paths = AGENT.flat_map { |pattern| pattern.include?("*") ? Dir.glob(File.join(user_home, pattern)) : File.join(user_home, pattern) }
  end
end
