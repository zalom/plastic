# encoding: UTF-8
# frozen_string_literal: true

require "rubygems"

# Pure, dependency-injected pre-flight checks for Plastic's runtime dependencies
# (intent 38). Takes injected probes (ruby version, node version, git presence,
# mise presence) and returns a plain decision: ok / fatal plus branded messages.
#
# No I/O, no shelling out, no ENV reads here. Callers (scripts/install.rb,
# bin/plastic.js) own the impure probing and the printing, so this module stays
# hermetically testable. Voice matches boot_banner.rb (understated, "Plastic ..."
# prefix); no em-dash, no en-dash in any message.
module Preflight
  module_function

  RUBY_FLOOR = "3.0.0"
  NODE_FLOOR = 18
  RUBY_PIN = "3.3"

  def check(ruby_version:, node_version:, git_present:, mise_present:)
    messages = []

    ruby_message = ruby_issue(ruby_version, mise_present)
    fatal = !ruby_message.nil?
    messages << ruby_message if ruby_message

    node_message = node_issue(node_version)
    messages << node_message if node_message

    git_message = git_issue(git_present)
    messages << git_message if git_message

    { ok: messages.empty?, fatal: fatal, messages: messages }
  end

  def ruby_issue(ruby_version, mise_present)
    parsed = safe_version(ruby_version)
    return nil if parsed && parsed >= safe_version(RUBY_FLOOR)

    lines = []
    lines << "Plastic needs Ruby #{RUBY_FLOOR} or newer to run its scripts (found #{found(ruby_version)})."
    lines << "Install a pinned Ruby with mise:"
    lines << "  curl https://mise.run | sh        # only if mise is not installed yet" unless mise_present
    lines << "  mise use --global ruby@#{RUBY_PIN}"
    lines << "Then re-run the Plastic installer."
    lines.join("\n")
  end

  def node_issue(node_version)
    parsed = safe_version(strip_leading_v(node_version))
    return nil if parsed && parsed >= safe_version(NODE_FLOOR.to_s)

    "Plastic works best on Node #{NODE_FLOOR} or newer (found #{found(node_version)}). " \
      "Pin it with mise: mise use --global node@25"
  end

  def git_issue(git_present)
    return nil if git_present

    "Plastic uses git for its store and worktrees (git was not found). " \
      "Install git, e.g. macOS: xcode-select --install"
  end

  def safe_version(str)
    Gem::Version.new(str.to_s)
  rescue ArgumentError
    nil
  end

  def strip_leading_v(str)
    str.to_s.strip.sub(/\Av/, "")
  end

  def found(value)
    text = value.to_s.strip
    text.empty? ? "not found" : text
  end
end
