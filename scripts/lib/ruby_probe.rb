# encoding: UTF-8
# frozen_string_literal: true

# Which ruby would a spawned Plastic hook actually get, and what version is it?
# Intent 235, D6. Pure and dependency injected: the capture seam is a lambda, so
# tests never spawn a process and never touch ENV.
#
# A hook is launched by the agent application, not by a login shell, so a version
# manager that activates on shell prompt render (mise, rbenv, asdf) may never reach
# it and bare `ruby` can still resolve to the system interpreter. Doctor reports
# that. It never repairs it.
#
# Mechanism, and why it is honest:
#   - The command word is the bare name "ruby", so the operating system resolves it
#     on the inherited PATH exactly the way it does for a spawned bash launcher. We
#     do not read PATH ourselves and we do not reimplement the search.
#   - The resolved interpreter answers for itself: RUBY_VERSION is its own version,
#     RbConfig.ruby is its own absolute path. One spawn, no guessing.
#   - RUBYOPT is cleared, matching what every Plastic launcher now does. That makes
#     this the honest simulation of the post-fix world, and it stops the probe from
#     crashing on the exact machine that most needs the report (an old ruby plus a
#     shell that exports RUBYOPT=--yjit).
module RubyProbe
  module_function

  # A hash passed as the first argument MERGES onto the inherited environment. It
  # clears nothing unless the key is present with a nil or empty value, so the nil
  # here is load bearing.
  CLEARED_ENV = { "RUBYOPT" => nil }.freeze

  PROBE_ARGS = ["-rrbconfig", "-e", "puts RUBY_VERSION; puts RbConfig.ruby"].freeze

  def default_capture
    lambda do |env, command, *args|
      require "open3"
      out, _err, status = Open3.capture3(env, command, *args)
      [out, status.success?]
    rescue Errno::ENOENT
      ["", false] # no ruby on PATH: undetectable, fail open
    end
  end

  # => { found: true, version: "3.3.5", path: "/opt/ruby/bin/ruby" }
  # => { found: false, version: nil, path: nil } on any trouble at all.
  def resolve(capture: default_capture)
    out, ok = capture.call(CLEARED_ENV, "ruby", *PROBE_ARGS)
    return not_found unless ok

    version, path = out.to_s.lines.map(&:strip).reject(&:empty?)
    return not_found if version.nil? || version.empty?

    { found: true, version: version, path: path }
  rescue StandardError
    not_found
  end

  def not_found
    { found: false, version: nil, path: nil }
  end
end
