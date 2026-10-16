# frozen_string_literal: true

require_relative "../../test_helper"
require "yaml"
require_relative "../../support/child_process"

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
  ROOT = File.expand_path("../../..", __dir__)
  SELF = "test/plastic/layout/kernel_paths_test.rb"
  OLD_KERNEL = File.join("scripts", "lib", "plastic")
  MOVED_TOOLS = %w[scripts/build-release scripts/release-check scripts/lib/release_archive scripts/lib/release_build
    scripts/lib/release_guard].freeze
  RETIRED_NAMES = [OLD_KERNEL, *MOVED_TOOLS, *RetiredNames::RETIRED_COMMANDS].freeze
  WORKFLOW_NAME = Regexp.union(RetiredNames::RETIRED_WORKFLOWS.map { |name| /#{Regexp.escape(name)}(?![A-Za-z0-9_])/ })

  def tracked
    @tracked ||= ChildProcess.capture2e("git", "ls-files", "-z", chdir: ROOT).first.split("\0").reject do |path|
      path == "CHANGELOG.md" || path == SELF || !File.file?(File.join(ROOT, path))
    end
  end

  def text_of(path)
    text = File.read(File.join(ROOT, path), encoding: "UTF-8")
    text.valid_encoding? ? text : nil
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
    files = kernel + [File.join(ROOT, "scripts", "lib", "installer_core.rb"), File.join(ROOT, "scripts", "install.rb")]

    assert_empty files.reject { |file| loads_alone?(file) }
  end

  def loads_alone?(file)
    code = %(require "plastic"; load ARGV.fetch(0) unless ARGV.fetch(0).end_with?("install.rb"))
    _out, status = ChildProcess.capture2e(RbConfig.ruby, "-I", File.join(ROOT, "lib"), "-I", File.join(ROOT, "scripts", "lib"),
      "-e", code, file, chdir: ROOT)
    status.success?
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
