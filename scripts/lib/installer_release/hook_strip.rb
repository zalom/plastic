# frozen_string_literal: true

require "json"

module InstallerRelease
  # Removes the hook groups that run one of Plastic's launchers before the
  # active release writes its own, so a rollback leaves no hook the older
  # release does not have. A group is Plastic's only when a command names a
  # launcher path in quotes, never by a substring of a name.
  class HookStrip
    def initialize(files:, launchers:)
      @files = files
      @launchers = launchers.map { |path| %("#{path}") }
    end

    def call = files.select { |path| File.file?(path) }.each { |path| strip(path) }

    private

    attr_reader :files, :launchers

    def strip(path)
      data = JSON.parse(File.read(path))
      hooks = data["hooks"]
      return unless hooks.is_a?(Hash)

      File.write(path, "#{JSON.pretty_generate({ **data, "hooks" => kept(hooks) })}\n")
    end

    def kept(hooks) = hooks.transform_values { |groups| theirs(groups) }.reject { |_event, groups| groups.empty? }

    def theirs(groups) = Array(groups).reject { |group| ours?(group) }

    def ours?(group) = Array(group["hooks"]).any? { |hook| launcher?(hook["command"].to_s) }

    def launcher?(command) = launchers.any? { |launcher| command.include?(launcher) }
  end
end
