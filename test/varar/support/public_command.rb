# frozen_string_literal: true

require "fileutils"
require "open3"
require "rbconfig"

# Runs the repository's own bin/plastic in a disposable home: HOME,
# PLASTIC_HOME and PLASTIC_TMP all point inside the directory it is given.
class PublicCommand
  PLASTIC = File.expand_path("../../../bin/plastic", __dir__)

  attr_reader :home, :global

  def initialize(home)
    @home = home
    @global = File.join(home, ".plastic", "stores", "global")
    FileUtils.mkdir_p(File.join(@global, "store"))
    File.write(File.join(@global, "INDEX.md"), "# Index\n\n## Active\n\n## Completed\n\n## Abandoned\n")
    @env = {"HOME" => home, "PLASTIC_HOME" => File.join(home, ".plastic"), "PLASTIC_TMP" => File.join(home, "tmp"),
            "CLAUDE_CODE_SESSION_ID" => nil, "RUBYOPT" => nil, "BUNDLER_SETUP" => nil,
            "GIT_CONFIG_GLOBAL" => File.join(home, ".gitconfig"), "GIT_CONFIG_SYSTEM" => "/dev/null"}
  end

  # [exit status, stdout, stderr]
  def run(*args)
    out, err, status = Open3.capture3(@env, RbConfig.ruby, PLASTIC, *args, chdir: @home)
    [status.exitstatus, out, err]
  end
end
