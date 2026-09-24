# encoding: UTF-8
# frozen_string_literal: true

require_relative "version_number"

# Pure, dependency-injected pre-flight checks for Plastic's runtime dependencies
# (intent 38, narrowed by intent 391). Takes injected probes (ruby version, git
# presence, sqlite3 presence, platform) and returns a plain decision: ok / fatal
# plus branded messages.
#
# No I/O, no shelling out, no ENV reads here. Callers (scripts/install.rb,
# bin/plastic.js) own the impure probing and the printing, so this module stays
# hermetically testable. Voice matches boot_banner.rb (understated, "Plastic ..."
# prefix); no em-dash, no en-dash in any message.
module Preflight
  module_function

  RUBY_FLOOR = "4.0.0"
  RUBY_PIN = "4.0"

  def check(ruby_version:, git_present:, sqlite3_present:, platform:)
    messages = []

    ruby_message = ruby_issue(ruby_version)
    messages << ruby_message if ruby_message

    git_message = git_issue(git_present, platform)
    messages << git_message if git_message

    sqlite3_message = sqlite3_issue(sqlite3_present, platform)
    messages << sqlite3_message if sqlite3_message

    fatal = !(ruby_message.nil? && git_message.nil? && sqlite3_message.nil?)
    { ok: messages.empty?, fatal: fatal, messages: messages }
  end

  def ruby_issue(ruby_version)
    parsed = safe_version(ruby_version)
    return nil if parsed && parsed >= safe_version(RUBY_FLOOR)

    lines = []
    lines << "Plastic needs Ruby #{RUBY_FLOOR} or newer to run its scripts (found #{found(ruby_version)})."
    lines << "Install a pinned Ruby with mise:"
    lines << "  curl https://mise.run | sh        # only if mise is not installed yet"
    lines << "  mise use --global ruby@#{RUBY_PIN}"
    lines << "Then re-run the Plastic installer."
    lines.join("\n")
  end

  def git_issue(git_present, platform)
    return nil if git_present

    "Plastic uses git for its store and worktrees (git was not found).\n" \
      "next: #{install_command(platform, "git")}"
  end

  def sqlite3_issue(sqlite3_present, platform)
    return nil if sqlite3_present

    "Plastic uses sqlite3 for its search index (sqlite3 was not found).\n" \
      "next: #{install_command(platform, "sqlite3")}"
  end

  def install_command(platform, package)
    if platform.to_s == "linux"
      "sudo apt-get install -y #{package}"
    else
      "xcode-select --install"
    end
  end

  def safe_version(str)
    VersionNumber.parse(str)
  end

  def found(value)
    text = value.to_s.strip
    text.empty? ? "not found" : text
  end
end
