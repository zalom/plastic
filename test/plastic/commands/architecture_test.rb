# frozen_string_literal: true

require_relative "../../test_helper"
require "json"
require "open3"
require "digest"

class ArchitectureTest < Plastic::TestCase
  def test_reports_a_missing_architecture_snapshot_as_json_and_lists_its_refresh_command
    status = plastic("architecture", "status", "--json", table: Plastic::CLI::TABLE)
    help = plastic("architecture", "refresh", "--help", table: Plastic::CLI::TABLE)

    assert_equal 0, status.code, status.err
    assert_equal "missing", JSON.parse(status.out).dig("result", "architecture", "state")
    assert_includes help.out, "plastic architecture refresh"
  end

  def test_marks_a_second_dirty_worktree_edit_as_stale
    Dir.mktmpdir do |repository|
      prepare_repository(repository)
      write_snapshot(repository)
      File.write(File.join(repository, "source.rb"), "first edit\n")
      store_receipt("revision" => revision(repository), "worktree_hash" => worktree_hash(repository))
      File.write(File.join(repository, "source.rb"), "second edit\n")

      assert_equal "stale", architecture_status(repository).dig("result", "architecture", "state")
    end
  end

  def test_uses_the_registered_project_root_from_a_subdirectory
    Dir.mktmpdir do |repository|
      prepare_repository(repository)
      write_snapshot(repository, dirty: false)
      register_project("other", repository)
      nested = File.join(repository, "nested")
      FileUtils.mkdir_p(nested)

      assert_equal "fresh", architecture_status(nested, arguments: ["--project", "other"]).dig("result", "architecture", "state")
    end
  end

  def test_preserves_the_selected_project_in_the_refresh_next_step
    Dir.mktmpdir do |repository|
      prepare_repository(repository)
      register_project("other", repository)

      result = architecture_status(repository, arguments: ["--project", "other"])

      assert_equal "plastic architecture refresh --project other", result.fetch("next")
    end
  end

  private

  def architecture_status(repository, arguments: [])
    out = StringIO.new
    error = StringIO.new
    result = Plastic::CLI.call(["architecture", "status", *arguments, "--json"], environment: command_environment(out, error, repository), table: Plastic::CLI::TABLE)

    assert_equal 0, result, error.string

    JSON.parse(out.string)
  end

  def command_environment(out, error, repository)
    Plastic::CLI::Command::Environment.new(env: { "PLASTIC_HOME" => @plastic_home }, input: StringIO.new,
      out:, err: error, home: @home, directory: repository)
  end

  def prepare_repository(repository)
    File.write(File.join(repository, ".gitignore"), ".enola/\n")
    File.write(File.join(repository, "source.rb"), "original\n")
    run_git(repository, "init")
    run_git(repository, "add", ".")
    run_git(repository, "commit", "-m", "initial")
  end

  def write_snapshot(repository, dirty: true)
    root = File.join(repository, ".enola")
    FileUtils.mkdir_p(root)
    hashes = %w[facts.jsonl llm_context.md].to_h do |name|
      path = File.join(root, name)
      File.write(path, name)
      [name, "sha256:#{Digest::SHA256.file(path).hexdigest}"]
    end
    data = { "repo_path" => repository, "git" => { "commit" => revision(repository), "dirty" => dirty },
             "extractors" => ["ruby"], "extractor_version" => "v265", "quality" => {}, "output_hashes" => hashes }
    File.write(File.join(root, "snapshot.meta.json"), JSON.generate(data))
  end

  def revision(repository) = run_git(repository, "rev-parse", "HEAD").strip

  def worktree_hash(repository)
    status = run_git(repository, "status", "--porcelain", "--untracked-files=all")
    Digest::SHA256.hexdigest(status.lines.map { |line| dirty_file_digest(repository, line) }.join)
  end

  def dirty_file_digest(repository, line)
    path = line[3..].to_s.strip
    [line, Digest::SHA256.file(File.join(repository, path)).hexdigest].join("\0")
  end

  def run_git(repository, *arguments)
    output, error, status = Open3.capture3("git", "-C", repository, *arguments)
    raise error unless status.success?

    output
  end

  def store_receipt(receipt)
    Plastic::Graph.open(home: @plastic_home, store: "global").databases.fetch(:knowledge).transaction do |batch|
      batch.put(:architecture_receipts, { provider: "enola", data: JSON.generate(receipt), updated_at: Plastic.now })
    end
  end

  def register_project(slug, path)
    File.write(File.join(@plastic_home, "projects.yml"), "projects:\n  #{slug}:\n    path: #{path}\n")
    FileUtils.mkdir_p(File.join(@plastic_home, "stores", slug))
    Plastic::Graph.open(home: @plastic_home, store: slug)
  end
end
