# frozen_string_literal: true

require_relative "test_helper"
require "yaml"
require_relative "support/child_process"
require_relative "support/repository_files"

# The names that left the kernel: a tracked file naming one is a stale reference.
module RetiredNames
  RETIRED_COMMANDS = [
    "Commands::ConfigList", "Commands::ConfigGet", "Commands::ConfigSet", "Commands::IntentAbandon",
    "Commands::IntentEnd", "Commands::IntentNew", "Commands::ProjectList", "Commands::ProjectNew",
    "Commands::ProjectLinks", "Commands::SyncUp", "Commands::SyncDown", "Commands::SessionNote",
    "Commands::IntentRule", "Commands::IntentRevise", "Commands::IntentNote", "Commands::IntentApprove",
    "Commands::IntentJudge", "Commands::IntentVerdict", "Commands::IntentSpec", "Commands::IntentDiscover",
    "Commands::IntentContext", "Commands::ArchitectureStatus", "Commands::ArchitectureRefresh", "Commands::IntentLockStatus",
    "Commands::IntentShow", "Commands::IntentBrief", "Commands::IntentLink", "Commands::IntentUnlink",
    "Commands::IntentArchive", "Commands::IntentUnarchive", "Commands::BackupList", "Commands::BackupPurge",
    "Commands::BackupRestore", "Commands::DocumentGet", "Commands::DocumentBatch", "Commands::NodeAdd",
    "Commands::NodeRemove", "Commands::NodeClaim", "Commands::NodeRelease", "Commands::NodeDone",
    "Commands::NodeFail", "Commands::NodeAsk", "Commands::NodeImpede", "Commands::NodeResolve",
    "Commands::EdgeAdd", "Commands::EdgeRemove", "Commands::GraphCheck", "Commands::GraphReady",
    "Commands::GraphResume", "Commands::GraphShow", "Commands::RoadmapNew", "Commands::RoadmapBatch",
    "Commands::RoadmapAdd", "Commands::RoadmapShow", "Commands::RoadmapNext", "Commands::RoadmapDrop",
    "Commands::RoadmapOpen", "Commands::RoadmapCheck", "Commands::RoadmapLog", "Commands::RoadmapEdgeRemove"
  ].freeze
  RETIRED_WORKFLOWS = [
    "Workflows::WriteIntent", "Workflows::SyncUp", "Workflows::PreviewSync", "Workflows::SyncDown", "Workflows::PreviewSyncDown",
    "Workflows::AddRuling", "Workflows::ReviseIntent", "Workflows::NoteIntent", "Workflows::ShowSpec", "Workflows::ApproveIntent",
    "Workflows::PrepareJudge", "Workflows::JudgeIntent", "Workflows::RecordVerdict", "Workflows::PrepareVerdict", "Workflows::StartAuto",
    "Workflows::PickDelivery", "Workflows::ShowLock", "Workflows::CheckGraph", "Workflows::ReadyGraph", "Workflows::ShowGraph",
    "Workflows::ShowIntent", "Workflows::ShowBrief", "Workflows::DeliveryNext", "Workflows::PickNext", "Workflows::AddLink",
    "Workflows::RemoveLink", "Workflows::CreateRoadmap", "Workflows::WriteRoadmapBatch", "Workflows::AddRoadmapItem", "Workflows::ShowRoadmap",
    "Workflows::NextRoadmap", "Workflows::DropRoadmapItem", "Workflows::OpenRoadmapItem", "Workflows::CheckRoadmap", "Workflows::LogRoadmap",
    "Workflows::RemoveRoadmapEdge", "Workflows::AdvanceDelivery", "Workflows::CloseIntent", "Workflows::PrepareEnding", "Workflows::FinishIntent",
    "Workflows::CheckMerge", "Workflows::WindDownIntent", "Workflows::DiscoverRetrieval", "Workflows::ExternalAgentWorkflow", "Workflows::Search",
    "Workflows::GetDocument", "Workflows::BatchDocuments", "Workflows::SubmitContext", "Workflows::CheckContextOwner", "Workflows::ReadContext",
    "Workflows::CheckArchitecture", "Workflows::RefreshArchitecture", "Workflows::AbandonIntent", "Workflows::PrepareAbandon", "Workflows::RevertIntent",
    "Workflows::WriteNote", "Workflows::ArchiveIntent", "Workflows::UnarchiveIntent", "Workflows::Backup", "Workflows::PreviewBackup",
    "Workflows::BackupList", "Workflows::BackupPurge", "Workflows::PreviewBackupPurge", "Workflows::BackupRestore", "Workflows::PreviewBackupRestore",
    "Workflows::ShowVersion", "Workflows::CheckHealth", "Workflows::InstallPlastic", "Workflows::PreviewInstall", "Workflows::OfferEnola",
    "Workflows::InstallHarnesses", "Workflows::ChooseHarnesses", "Workflows::UninstallPlastic", "Workflows::PreviewUninstall", "Workflows::ChooseInstallations",
    "Workflows::UpdatePlastic", "Workflows::PreviewUpdate", "Workflows::RollbackRelease", "Workflows::PreviewRollback", "Workflows::AddNode",
    "Workflows::RemoveNode", "Workflows::ClaimNode", "Workflows::ReleaseNode", "Workflows::DoneNode", "Workflows::FailNode",
    "Workflows::AskNode", "Workflows::ImpedeNode", "Workflows::ResolveNode", "Workflows::AddEdge", "Workflows::RemoveEdge",
    "ExternalAgentWorkflow", "PreviewSyncDown"
  ].freeze
end

class KernelPathsTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SELF = "test/kernel_paths_guard_test.rb"
  OLD_KERNEL = File.join("scripts", "lib", "plastic")
  MOVED_TOOLS = %w[scripts/build-release scripts/release-check scripts/lib/release_archive scripts/lib/release_build
    scripts/lib/release_guard].freeze
  RETIRED_NAMES = [OLD_KERNEL, *MOVED_TOOLS, *RetiredNames::RETIRED_COMMANDS].freeze
  WORKFLOW_NAME = Regexp.union(RetiredNames::RETIRED_WORKFLOWS.map { |name| /#{Regexp.escape(name)}(?![A-Za-z0-9_])/ })

  def tracked
    @tracked ||= RepositoryFiles.paths(ROOT).reject { |path| path == "CHANGELOG.md" || path == SELF }
  end

  def text_of(path)
    text = File.read(File.join(ROOT, path), encoding: "UTF-8")
    text.valid_encoding? ? text : nil
  end

  def test_the_subjects_are_read_from_the_disk
    refute_empty tracked
  end

  def test_no_tracked_file_names_the_old_kernel_path_or_a_retired_name
    hits = tracked.select do |path|
      text = text_of(path)
      text && (RETIRED_NAMES.any? { |name| text.include?(name) } || text.match?(WORKFLOW_NAME))
    end

    assert_empty hits
  end

  def test_no_ruby_file_joins_the_old_kernel_path_from_words
    joined = /["']scripts["'],\s*["']lib["'],\s*["']plastic["']/
    hits = tracked.select { |path| path.end_with?(".rb") && text_of(path)&.match?(joined) }

    assert_empty hits
  end

  def test_the_kernel_lives_under_lib
    assert File.file?(File.join(ROOT, "lib", "plastic.rb"))
    assert File.directory?(File.join(ROOT, "lib", "plastic", "commands"))
  end

  def test_nothing_of_the_kernel_stays_under_scripts_lib
    refute_path_exists File.join(ROOT, "scripts", "lib", "plastic.rb")
    refute_path_exists File.join(ROOT, "scripts", "lib", "plastic")
  end

  def test_the_dir_relative_constants_point_into_the_package
    require "plastic/cli"
    require "plastic/workflows/installation"
    require "plastic/workflows/code/intent/spec"

    assert File.file?(File.join(Plastic::Workflows::Installation::PACKAGE_ROOT, "package.json"))
    assert_predicate Dir.glob(File.join(Plastic::CLI::TOPICS, "*.md")), :any?
    assert File.file?(Plastic::Workflows::Code::Intent::Spec::GRILLING)
  end

  def test_a_fresh_process_requires_every_kernel_file_and_the_installer
    kernel = Dir.glob(File.join(ROOT, "lib", "plastic", "**", "*.rb"))

    refute_empty kernel

    assert_empty failing_loads(kernel)
  end

  FORKED_LOADS = <<~'CODE'
    require "plastic"
    ARGV.each do |file|
      pid = fork { GC.disable; exit!(begin; load(file); true; rescue Exception; false; end ? 0 : 1) }
      puts("FAILED #{file}") unless Process.wait2(pid).last.success?
    end
  CODE

  def failing_loads(files)
    runs = files.each_slice((files.size / 24.0).ceil).map { |slice| Thread.new { forked_loads(slice) } }
    runs.flat_map(&:value)
  end

  def forked_loads(files)
    out, = ChildProcess.capture2e(RbConfig.ruby, "-W0", "-I", File.join(ROOT, "lib"), "-e", FORKED_LOADS, *files, chdir: ROOT)
    out.lines.grep(/\AFAILED /).map { |line| line.chomp.delete_prefix("FAILED ") }
  end

def test_requiring_plastic_loads_the_core_and_no_cli
  out, = ChildProcess.capture2e(RbConfig.ruby, "-W0", "-I", File.join(ROOT, "lib"), "-e", %(require "plastic"; print defined?(Plastic::CLI).inspect), chdir: ROOT)

  assert_equal "nil", out
end

ENTRY_POINTS = { "exe/plastic" => %(require_relative "../lib/plastic/cli"), "tools/command_reference.rb" => %(require "plastic/cli"),
                 "test/test_helper.rb" => %(require "plastic/cli") }.freeze

def test_every_entry_point_requires_the_cli_by_name
  stale = ENTRY_POINTS.reject { |path, line| File.read(File.join(ROOT, path), encoding: "UTF-8").include?(line) }

  assert_empty stale.keys
end

  def test_the_test_helper_covers_lib
    helper = File.read(File.join(ROOT, "test", "test_helper.rb"))

    assert_match(/cover "\{[^}]*\blib\b[^}]*\}/, helper)
  end

  def lint_debt_paths
    todo = YAML.load_file(File.join(ROOT, ".rubocop_todo.yml")).values.flat_map { |entry| entry.is_a?(Hash) ? Array(entry["Exclude"]) : [] }
    todo + Array(YAML.load_file(File.join(ROOT, ".reek.yml"))["exclude_paths"])
  end

  def test_every_path_the_lint_debt_names_exists
    named = lint_debt_paths.grep(%r{\A(lib|scripts|bin|tools)/.+\.rb\z})

    assert_empty(named.reject { |path| File.exist?(File.join(ROOT, path)) })
  end
end
