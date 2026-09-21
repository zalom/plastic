# frozen_string_literal: true

# Plastic::CLI::TABLE (intent 363) - the whole command line in one frozen hash:
# a command name mapped to the file that holds it, the class inside
# Plastic::CLI::Commands, and the one line `plastic help` prints beside it.
#
# Adding a command is one row here plus one file. `plastic help` reads this
# hash and loads nothing, so listing the commands costs no command file.
# test/cli/table_test.rb walks every row, so a half-wired command cannot ship.
module Plastic
  class CLI
    TABLE = {
      "auto brief" => ["commands/auto_brief", "AutoBrief", "Print an intent's spawn preamble, and the advisor shapes for --role advisor"],
      "auto lock" => ["commands/auto_lock", "AutoLock", "Inspect, repair, or release an intent's delivery lock"],
      "auto report" => ["commands/auto_report", "AutoReport", "Print an intent's completion report, then the review-by-risk rules"],
      "auto take" => ["commands/auto_take", "AutoTake", "Arm an intent's delivery lock for this session"],
      "auto" => ["commands/auto", "Auto", "List the auto subcommands"],
      "checkout" => ["commands/checkout", "Checkout", "Restore missing store files from the databases"],
      "continue" => ["commands/continue", "Continue", "Show where one project stands and what runs next"],
      "doctor" => ["commands/doctor", "Doctor", "Diagnose Plastic installation health"],
      "feedback" => ["commands/feedback", "Feedback", "File a feedback report, body on standard input"],
      "help" => ["commands/help", "Help", "List the commands and help topics, or show one usage"],
      "hook" => ["commands/hook", "Hook", "Run one harness hook event through its launcher"],
      "index" => ["commands/index", "Index", "Rebuild the search index from every markdown file in the stores"],
      "install" => ["commands/install", "Install", "Install Plastic into this machine's agents"],
      "intent" => ["commands/intent", "Intent", "List the intent subcommands"],
      "intent answer" => ["commands/intent_answer", "IntentAnswer", "Answer an intent's needs_decision node"],
      "intent end" => ["commands/intent_end", "IntentEnd", "Close an intent as delivered or abandoned"],
      "intent new" => ["commands/intent_new", "IntentNew", "Create a new intent"],
      "intent note" => ["commands/intent_note", "IntentNote", "Append a savepoint note to an intent"],
      "intent rule" => ["commands/intent_rule", "IntentRule", "Record a ruling in an intent's Insights"],
      "intent show" => ["commands/intent_show", "IntentShow", "Print an intent's state screen"],
      "intent spec" => ["commands/intent_spec", "IntentSpec", "Print an intent's state screen, then the speccing rules"],
      "intent step" => ["commands/intent_step", "IntentStep", "Run the next ready step of an intent's graph"],
      "intent verify" => ["commands/intent_verify", "IntentVerify", "Run an intent's merge-gate checks"],
      "next" => ["commands/next", "Next", "Print the next action in one line"],
      "project" => ["commands/project", "Project", "List the project subcommands"],
      "project links" => ["commands/project_links", "ProjectLinks", "Project every store's Links sections from frontmatter"],
      "project list" => ["commands/project_list", "ProjectList", "List every store this machine holds"],
      "project new" => ["commands/project_new", "ProjectNew", "Register, provision and validate a new project"],
      "query" => ["commands/query", "Query", "Run one read-only SQL statement on the index"],
      "render" => ["commands/render", "Render", "Print one markdown file as an HTML page"],
      "roadmap" => ["commands/roadmap", "Roadmap", "List the roadmap subcommands"],
      "roadmap check" => ["commands/roadmap_check", "RoadmapCheck", "Check a roadmap's graph for cycles and dangling ids"],
      "roadmap log" => ["commands/roadmap_log", "RoadmapLog", "Append a savepoint line to a roadmap's ledger"],
      "roadmap next" => ["commands/roadmap_next", "RoadmapNext", "Name the roadmap most worth continuing"],
      "roadmap show" => ["commands/roadmap_show", "RoadmapShow", "Print a roadmap's state screen"],
      "rollback" => ["commands/rollback", "Rollback", "Move to a Plastic version this machine has run before"],
      "search" => ["commands/search", "Search", "Find text in the stores, ranked, with one excerpt each"],
      "session commit" => ["commands/session_commit", "SessionCommit", "Commit one verified checklist item"],
      "session handoff" => ["commands/session_handoff", "SessionHandoff", "Write this session's hand-off into the day ledger"],
      "session summary" => ["commands/session_summary", "SessionSummary", "Print the day ledger's open items and recent activity"],
      "session" => ["commands/session", "Session", "List the session subcommands"],
      "status" => ["commands/status", "Status", "Show active work in every store"],
      "sync" => ["commands/sync", "Sync", "Bring the store files and the three databases level"],
      "uninstall" => ["commands/uninstall", "Uninstall", "Remove Plastic from this machine's agents"],
      "update" => ["commands/update", "Update", "Move Plastic to the next version on its channel"],
      "version" => ["commands/version", "Version", "Print the installed Plastic version"]
    }.freeze
  end
end
