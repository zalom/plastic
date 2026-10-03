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

      data["hooks"] = hooks.transform_values { |groups| Array(groups).reject { |group| ours?(group) } }.reject { |_event, groups| groups.empty? }
      File.write(path, "#{JSON.pretty_generate(data)}\n")
    end

    def ours?(group) = Array(group["hooks"]).any? { |hook| launchers.any? { |launcher| hook["command"].to_s.include?(launcher) } }
  end
end
