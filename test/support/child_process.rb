# frozen_string_literal: true

require "open3"
require "rbconfig"
require "tmpdir"

# Starts a child process of the suite with a clean environment: the values the
# test passes, a fixed PATH and LANG, and a fresh empty HOME when the test
# passes none. Nothing else of the running session reaches the child. Each
# call takes what Open3 or Kernel takes: an optional hash of values, then the
# command and its options.
module ChildProcess
  PATH = [File.dirname(RbConfig.ruby), "/usr/bin", "/bin"].join(File::PATH_SEPARATOR)
  FIXED = { "PATH" => PATH, "LANG" => "C.UTF-8" }.freeze

  def self.environment(values, home:) = FIXED.merge("HOME" => home).merge(values.transform_keys(&:to_s)).compact

  def self.capture3(*command, **options) = start(command) { |env, rest| Open3.capture3(env, *rest, unsetenv_others: true, **options) }

  def self.capture2(*command, **options) = start(command) { |env, rest| Open3.capture2(env, *rest, unsetenv_others: true, **options) }

  def self.capture2e(*command, **options) = start(command) { |env, rest| Open3.capture2e(env, *rest, unsetenv_others: true, **options) }

  def self.system(*command, **options) = start(command) { |env, rest| Kernel.system(env, *rest, unsetenv_others: true, **options) }

  def self.start(command)
    values, rest = command.first.is_a?(Hash) ? [command.first, command.drop(1)] : [{}, command]
    Dir.mktmpdir("child-home") { |home| yield environment(values, home:), rest }
  end
  private_class_method :start
end
