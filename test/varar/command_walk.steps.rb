# frozen_string_literal: true

require "varar"
require "shellwords"
require "tmpdir"
require_relative "support/kernel_command"

# One row of a command walk: the setup lines run in order on a fresh home,
# each one required to succeed, then the call itself, all as session s-1.
# A setup line `write PATH TEXT` writes TEXT, with \n as a line break, to
# PATH in the store instead of calling the command line, and `legacy`
# copies the legacy store fixture in. A cell drops the usage lines a brief
# prints, reads each time as TIME, each backup name as STAMP and each byte
# count as SIZE, and squeezes the spaces that align columns. A cell written as a code span is compared by
# the text inside it.
module CommandWalk
  SESSION = { "CLAUDE_CODE_SESSION_ID" => "s-1" }.freeze

  module_function

  def call(row)
    Dir.mktmpdir("varar-command-walk") do |home|
      kernel = KernelCommand.new(home)
      plain(row["setup"]).split(" ; ").reject { |line| line == "none" }.each { |line| set_up(kernel, line.shellsplit) }
      cells(kernel.run(*plain(row["call"]).shellsplit, env: SESSION))
    end
  end

  def plain(cell) = cell.delete_prefix("`").delete_suffix("`")

  def quoted(row, cells) = cells.to_h { |key, value| [key, row[key].to_s.start_with?("`") ? "`#{value}`" : value] }

  def set_up(kernel, words)
    return kernel.write(words[1], words[2].gsub("\\n", "\n")) if words.first == "write"
    return kernel.copy_legacy_store if words == ["legacy"]

    kernel.run!(*words, env: SESSION)
  end

  TIME = /\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2}/
  STAMP = /plastic-\d{8}-\d{6}/
  SIZE = /\d+ bytes/

  def normal(line) = line.gsub(TIME, "TIME").gsub(STAMP, "plastic-STAMP").gsub(SIZE, "SIZE bytes").squeeze(" ")

  def cells(call)
    lines = call.out.lines(chomp: true).map { |line| normal(line) }
    { "exit" => call.code.to_s, "result" => result(call), "next line" => next_line(lines),
      "first line" => (lines.first || call.reason).to_s, "open lines" => open_lines(lines) }
  end
end

module CommandWalk
  module_function

  def result(call)
    said = call.said.reject { |line| line.start_with?("plastic ") }.map { |line| normal(line) }
    [*said, *(call.reason unless call.code.zero?)].join(" / ").then { |text| text.empty? ? "none" : text }
  end

  def next_line(lines)
    lines.find { |line| line.start_with?("next: ") }.to_s.delete_prefix("next: ").then { |text| text.empty? ? "none" : text }
  end

  def open_lines(lines) = lines.grep(/\Aopen: /).join(" / ").then { |text| text.empty? ? "none" : text }
end

steps do
  sensor("the setup, the call, the exit code, the result and the next line") do |_state, row|
    row.merge(CommandWalk.quoted(row, CommandWalk.call(row).slice("exit", "result", "next line")))
  end

  sensor("the setup, the call, the exit code, the first line, the open lines and the next line") do |_state, row|
    row.merge(CommandWalk.quoted(row, CommandWalk.call(row).slice("exit", "first line", "open lines", "next line")))
  end
end
