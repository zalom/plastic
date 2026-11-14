# frozen_string_literal: true

require_relative "support/install_sh_helper"

# install.sh needs curl, tar, a checksum tool, git and Ruby 4.0 or later. When one is
# missing it stops before it downloads anything and names what to install on macOS and
# on Linux.
class InstallShDependencyTest < Minitest::Test
  include InstallShHelper

  BASE_TOOLS = %w[mktemp rm mkdir ln cat cp uname dirname basename chmod].freeze

  def test_each_missing_tool_is_named_with_both_platforms
    path = machine(tools: %w[tar], fakes: [])
    out, err, status = run_script(path)

    assert_equal [1, ""], [status.exitstatus, out]
    assert_empty ["needs curl", "needs git", "needs Ruby 4.0", "needs sha256sum or shasum", "macOS:", "Linux:"].reject { |text| err.include?(text) }, err
  end

  def test_no_ruby_is_named_with_a_command_for_each_platform
    _out, err, status = run_script(machine(fakes: %w[curl git sha256sum]))

    refute_equal 0, status.exitstatus
    assert_match(/needs Ruby 4\.0 or later.*macOS: .*brew.*Linux: /m, err)
  end

  def test_ruby_2_6_is_named_as_too_old_and_asks_for_4_0
    _out, err, status = run_script(machine(fakes: %w[curl git sha256sum], ruby: "2.6.10"))

    refute_equal 0, status.exitstatus
    assert_includes err, "needs Ruby 4.0 or later; found 2.6.10"
  end

  def test_no_git_is_named_with_a_command_for_each_platform
    _out, err, status = run_script(machine(fakes: %w[curl sha256sum], ruby: "4.0.7"))

    refute_equal 0, status.exitstatus
    assert_match(/needs git.*macOS: .*Linux: /m, err)
  end

  def test_no_ruby_and_no_git_are_both_named
    _out, err, = run_script(machine(fakes: %w[curl sha256sum]))

    assert_empty ["needs Ruby 4.0", "needs git"].reject { |text| err.include?(text) }, err
  end

  def test_a_missing_plastic_ruby_counts_as_no_ruby
    path = machine(fakes: %w[curl git sha256sum], ruby: "4.0.7")
    _out, err, status = run_script(path, "PLASTIC_RUBY" => File.join(@dir, "nowhere", "ruby"))

    refute_equal 0, status.exitstatus
    assert_includes err, "needs Ruby 4.0"
  end

  def test_an_old_plastic_ruby_counts_as_too_old
    old = File.join(@dir, "old-ruby")
    write_fake(old, "ruby", "2.6.10")
    path = machine(fakes: %w[curl git sha256sum], ruby: "4.0.7")
    _out, err, status = run_script(path, "PLASTIC_RUBY" => File.join(old, "ruby"))

    refute_equal 0, status.exitstatus
    assert_includes err, "found 2.6.10"
  end

  def test_a_stop_for_a_missing_tool_calls_no_curl_and_leaves_the_home_empty
    run_script(machine(fakes: %w[curl sha256sum]))

    assert_equal [false, []], [File.exist?(curl_log), Dir.children(@home)]
  end

  def test_a_beta_version_is_refused_and_names_plastic_update
    _out, err, status = run_script(machine(fakes: %w[curl git sha256sum], ruby: "4.0.7"), "PLASTIC_VERSION" => "9.9.9-beta.1")

    refute_equal 0, status.exitstatus
    assert_includes err, "plastic update"
    assert_equal [false, []], [File.exist?(curl_log), Dir.children(@home)]
  end

  def test_an_alpha_version_is_refused_and_names_plastic_update
    _out, err, status = run_script(machine(fakes: %w[curl git sha256sum], ruby: "4.0.7"), "PLASTIC_VERSION" => "9.9.8-alpha.2")

    refute_equal 0, status.exitstatus
    assert_includes err, "plastic update"
  end

  private

  def curl_log = File.join(@dir, "curl.log")

  def run_script(path, env = {})
    ChildProcess.capture3({ "HOME" => @home, "PATH" => path }.merge(env), "/bin/sh", SCRIPT)
  end

  # A PATH folder holding the real tools named and the fakes: curl writes each call to a log, git and
  # sha256sum answer, and ruby prints the version asked for.
  def machine(tools: [], fakes: [], ruby: nil)
    bin = File.join(@dir, "minbin")
    FileUtils.mkdir_p(bin)
    (BASE_TOOLS + %w[tar] + tools).uniq.each { |tool| File.symlink(which(tool), File.join(bin, tool)) unless File.exist?(File.join(bin, tool)) }
    fakes.each { |tool| File.write(File.join(bin, tool), fake(tool)) && File.chmod(0o755, File.join(bin, tool)) }
    write_fake(bin, "ruby", ruby) if ruby
    bin
  end

  def write_fake(folder, name, version)
    FileUtils.mkdir_p(folder)
    File.write(File.join(folder, name), "#!/bin/sh\necho \"ruby #{version}p1 (2026-01-01) [x86_64-linux]\"\n")
    File.chmod(0o755, File.join(folder, name))
  end

  def fake(tool)
    case tool
    when "curl" then "#!/bin/sh\necho \"$*\" >> #{curl_log}\nexit 1\n"
    when "sha256sum" then "#!/bin/sh\nexit 0\n"
    else "#!/bin/sh\necho \"#{tool} version 2.50.0\"\n"
    end
  end

  def which(tool)
    ENV.fetch("PATH").split(File::PATH_SEPARATOR).map { |dir| File.join(dir, tool) }.find { |path| File.executable?(path) }
  end
end
