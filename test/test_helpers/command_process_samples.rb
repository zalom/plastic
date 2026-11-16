# frozen_string_literal: true

# Sample source text for the child process guard: each way a test can start the tool, and text
# the guard must leave alone. The samples are text the guard parses, never code that runs.
module CommandProcessSamples
  CAUGHT = {
    "Process.spawn" => %(Process.spawn("ruby", "exe/plastic", "status")),
    "Kernel.system" => %(Kernel.system("ruby", "exe/plastic", "status")),
    "Kernel.spawn" => %(Kernel.spawn("ruby", "exe/plastic", "status")),
    "exec" => %(exec("ruby", "exe/plastic", "status")),
    "IO.popen" => %(IO.popen(["ruby", "exe/plastic", "status"]).read),
    "PTY.spawn" => %(PTY.spawn("ruby", "exe/plastic", "status")),
    "backticks" => "`ruby exe/plastic status`",
    "percent x" => "%x(ruby exe/plastic status)",
    "one shell string" => %(system("ruby exe/plastic status")),
    "launcher in a constant" => %(LAUNCHER = File.join(ROOT, "exe", "plastic")\nChildProcess.capture3(LAUNCHER, "status")),
    "launcher by expand_path" => %(ChildProcess.capture3(RbConfig.ruby, File.expand_path("../exe/plastic", __dir__), "status")),
    "launcher by join" => %(ChildProcess.capture3(File.join("exe", "plastic"), "status")),
    "kernel by ruby -e" => %(ChildProcess.capture3(RbConfig.ruby, "-e", "exit Plastic::CLI.call(ARGV)", "status")),
    "packaged bin/plastic" => %(ChildProcess.capture3(File.join(release, "bin", "plastic"), "status")),
    "Open3 with the launcher" => %(Open3.capture3("ruby", "exe/plastic", "status"))
  }.freeze

  LEFT_ALONE = {
    "a start that runs another program" => %(ChildProcess.capture3("git", "status")),
    "a backtick that runs another program" => "`git status`",
    "the launcher named with no start" => %(File.exist?("exe/plastic")),
    "the launcher joined with no start" => %(File.join(root, "bin", "plastic")),
    "the kernel named with no start" => %(Plastic::CLI.call(["status"])),
    "a start named inside a string" => %(text = "Process.spawn exe/plastic")
  }.freeze
end
