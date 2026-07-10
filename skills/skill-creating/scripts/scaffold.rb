#!/usr/bin/env ruby
# frozen_string_literal: true

# scaffold.rb - born-slim starting files for a new skill, agent, or hook.
#
# Plastic skills, agents, and hooks start small and grow by progressive
# disclosure. This scaffolder emits the minimum valid skeleton so the body
# stays slim and detail moves into references/ as the work earns it.
#
# Usage:
#   ruby scaffold.rb skill <name> [--out <dir>] [dest]
#   ruby scaffold.rb agent <name> [--out <dir>] [dest]
#   ruby scaffold.rb hook  [<Event>] <name> [--out <dir>] [dest]
#   ruby scaffold.rb --help
#
# All input is positional plus flags. There are no interactive prompts, so an
# agent never hangs waiting on input. The destination defaults to the current
# directory; pass --out or a trailing positional to choose another directory.
#
# Exit codes:
#   0  success, or --help
#   1  usage error (unknown subcommand, missing argument)
#   2  validation error (bad name or event)
#   3  refused to overwrite an existing target, or a filesystem error
#
# This script and every file it emits contain no em-dashes; the emitted files
# are user-facing.

require "json"
require "fileutils"

EXIT_OK = 0
EXIT_USAGE = 1
EXIT_VALIDATION = 2
EXIT_CONFLICT = 3

NAME_PATTERN = /\A[a-z0-9]+(-[a-z0-9]+)*\z/.freeze
EVENT_PATTERN = /\A[A-Z][A-Za-z]+\z/.freeze
DEFAULT_EVENT = "PostToolUse"

USAGE = <<~TEXT
  scaffold.rb - born-slim starting files for a new skill, agent, or hook.

  Usage:
    ruby scaffold.rb skill <name> [--out <dir>] [dest]
    ruby scaffold.rb agent <name> [--out <dir>] [dest]
    ruby scaffold.rb hook  [<Event>] <name> [--out <dir>] [dest]
    ruby scaffold.rb --help

  Subcommands:
    skill   Emit <dest>/<name>/SKILL.md, references/.gitkeep, evals/evals.json.
    agent   Emit <dest>/<name>.md agent role file.
    hook    Emit <dest>/<name> no-op hook handler (Ruby) wired for <Event>.

  Names must be lowercase alphanumeric and hyphens, with no leading,
  trailing, or repeated hyphens, 1 to 64 characters.
  The hook <Event> is optional and defaults to #{DEFAULT_EVENT}.
  The destination defaults to the current directory.

  Exit codes:
    0  success, or --help
    1  usage error (unknown subcommand, missing argument)
    2  validation error (bad name or event)
    3  refused to overwrite an existing target, or a filesystem error
TEXT

# A small error that carries the exit code to use when it reaches the top.
class ScaffoldError < StandardError
  attr_reader :code

  def initialize(message, code)
    super(message)
    @code = code
  end
end

def fail_with(message, code)
  raise ScaffoldError.new(message, code)
end

def validate_name!(name)
  if name.nil? || name.empty?
    fail_with("missing <name>. See --help for usage.", EXIT_USAGE)
  end
  unless name.length <= 64 && name =~ NAME_PATTERN
    fail_with(
      "invalid name #{name.inspect}: use lowercase letters, digits, and " \
      "hyphens, no leading, trailing, or repeated hyphens, 1 to 64 chars.",
      EXIT_VALIDATION
    )
  end
  name
end

def validate_event!(event)
  unless event =~ EVENT_PATTERN
    fail_with(
      "invalid event #{event.inspect}: use a CamelCase hook event name, " \
      "for example PostToolUse or SessionStart.",
      EXIT_VALIDATION
    )
  end
  event
end

# Separate --out and any trailing positional dest from the bare positionals.
# Returns [positionals, out_dir]. out_dir is nil when not given.
def parse_args(args)
  positionals = []
  out_dir = nil
  i = 0
  while i < args.length
    arg = args[i]
    case arg
    when "--out"
      out_dir = args[i + 1]
      if out_dir.nil?
        fail_with("--out needs a directory argument.", EXIT_USAGE)
      end
      i += 2
    else
      if arg.start_with?("--")
        fail_with("unknown option #{arg.inspect}. See --help for usage.", EXIT_USAGE)
      end
      positionals << arg
      i += 1
    end
  end
  [positionals, out_dir]
end

def refuse_if_exists!(path)
  if File.exist?(path)
    fail_with("refusing to overwrite existing #{path}. Remove it or pick another destination.", EXIT_CONFLICT)
  end
end

def write_file(path, content)
  refuse_if_exists!(path)
  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, content)
  puts "created #{path}"
end

# -- generators ----------------------------------------------------------

def skill_body(name)
  <<~MD
    ---
    name: #{name}
    description: >
      Use when the user needs #{name}. State here WHEN this skill should
      trigger, in the third person, so the agent can match it. Replace this
      placeholder with one or two concrete trigger conditions before shipping.
    ---

    # #{name}

    One line on what this skill does and why it exists.

    ## Gotchas

    - List the non-obvious failure modes here, one per line.

    ## Tasks

    Keep the body slim. Route detail to references as the work earns it.

    | Task | Reference |
    | ---- | --------- |
    | Replace this row with a real task | references/REPLACE-ME.md |
  MD
end

def eval_stub(name)
  data = {
    "skill_name" => name,
    "evals" => [
      {
        "id" => 1,
        "prompt" => "",
        "expected_output" => "",
        "files" => [],
        "assertions" => []
      }
    ]
  }
  JSON.pretty_generate(data) + "\n"
end

def generate_skill(name, out_dir)
  base = File.join(out_dir, name)
  refuse_if_exists!(base)
  write_file(File.join(base, "SKILL.md"), skill_body(name))
  write_file(File.join(base, "references", ".gitkeep"), "")
  write_file(File.join(base, "evals", "evals.json"), eval_stub(name))
  puts "skill scaffold ready at #{base}"
end

def agent_body(name)
  <<~MD
    ---
    name: #{name}
    description: >
      Use this agent when the user needs #{name}. State here WHEN to delegate
      to this agent, in the third person, so the orchestrator can route to it.
      Replace this placeholder with concrete delegation conditions.
    tools: Read, Edit, Bash
    ---

    You are the #{name} agent.

    ## Responsibilities

    - One line per durable responsibility this agent owns.

    ## How you work

    Keep this body slim. State the contract, the inputs, and the outputs.
    Move long procedures into a references file as the work earns it.

    ## Completion

    End your turn with a short report of what you did and how you verified it.
  MD
end

def generate_agent(name, out_dir)
  write_file(File.join(out_dir, "#{name}.md"), agent_body(name))
  puts "agent scaffold ready at #{File.join(out_dir, "#{name}.md")}"
end

def hook_body(name, event)
  <<~RUBY
    #!/usr/bin/env ruby
    # frozen_string_literal: true

    # #{name} - #{event} hook handler (no-op by default).
    #
    # This skeleton does nothing until you opt in. Set the environment flag
    # below to a non-empty value to activate the real behavior. Until then it
    # exits 0 so it never blocks the session.
    #
    # Wire it in settings.json under hooks.#{event}:
    #   { "type": "command", "command": "ruby /absolute/path/to/#{name}" }
    #
    # Exit codes:
    #   0  no-op, or success
    #   2  block the action (only when you add real logic that should block)

    OPT_IN = "#{name.tr("-", "_").upcase}_ENABLED"

    if ENV[OPT_IN].nil? || ENV[OPT_IN].empty?
      exit 0
    end

    # Opt-in is set. Add the real handler here. The hook receives event JSON on
    # stdin; parse it only when you need it. Exit 0 to allow, exit 2 to block.
    exit 0
  RUBY
end

def generate_hook(name, event, out_dir)
  path = File.join(out_dir, name)
  write_file(path, hook_body(name, event))
  FileUtils.chmod("+x", path)
  puts "hook scaffold ready at #{path} (executable, #{event}, no-op until opt-in)"
end

# -- dispatch ------------------------------------------------------------

def run(argv)
  if argv.empty? || argv.include?("--help") || argv.include?("-h")
    puts USAGE
    return EXIT_OK
  end

  subcommand = argv.shift
  positionals, out_flag = parse_args(argv)

  case subcommand
  when "skill", "agent"
    name = validate_name!(positionals[0])
    out_dir = out_flag || positionals[1] || "."
    subcommand == "skill" ? generate_skill(name, out_dir) : generate_agent(name, out_dir)
  when "hook"
    # Accept "hook <name>" or "hook <Event> <name>", with an optional trailing dest.
    if positionals.length >= 2 && positionals[0] =~ EVENT_PATTERN
      event = validate_event!(positionals[0])
      name = validate_name!(positionals[1])
      out_dir = out_flag || positionals[2] || "."
    else
      event = DEFAULT_EVENT
      name = validate_name!(positionals[0])
      out_dir = out_flag || positionals[1] || "."
    end
    generate_hook(name, event, out_dir)
  else
    fail_with("unknown subcommand #{subcommand.inspect}. See --help for usage.", EXIT_USAGE)
  end

  EXIT_OK
end

begin
  exit run(ARGV.dup)
rescue ScaffoldError => e
  warn "scaffold.rb: #{e.message}"
  exit e.code
rescue Errno::EACCES, Errno::ENOENT, Errno::EEXIST => e
  warn "scaffold.rb: filesystem error: #{e.message}"
  exit EXIT_CONFLICT
end
