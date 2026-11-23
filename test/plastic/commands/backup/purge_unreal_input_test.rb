# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/backup/purge"
require_relative "../../../../lib/plastic/commands/backup/list"

class BackupPurgeUnrealInputTest < Plastic::TestCase
  include BackupHomes

  STOPPED = "20260301100000"
  NOW = FixedClock::Clock.new(Time.utc(2026, 3, 1, 11, 0, 0))
  UNREAL = %w[20201399000000 20200231000000].freeze
  CORRUPT = { "a plain string" => "just text\n", "yaml that does not parse" => "status: [unclosed\n  - : :\n" }.freeze

  def folder(home, name, status_text: nil)
    FileUtils.mkdir_p(File.join(backups_dir(home), name))
    File.write(File.join(backups_dir(home), name, "status.yml"), status_text) if status_text
  end

  CORRUPT.each do |label, text|
    define_method(:"test_interrupted_deletes_a_folder_whose_status_file_is_#{label.tr(" ", "_")}") do
      home = fresh_home
      folder(home, STOPPED, status_text: text)
      result = purge_call(home, "--store", "alpha", "--interrupted", clock: NOW)

      assert_equal [0, []], [result.code, folder_names(home)]
    end

    define_method(:"test_failed_leaves_a_folder_whose_status_file_is_#{label.tr(" ", "_")}") do
      home = fresh_home
      folder(home, STOPPED, status_text: text)
      result = purge_call(home, "--store", "alpha", "--failed", clock: NOW)

      assert_equal [0, [STOPPED]], [result.code, folder_names(home)]
    end

    define_method(:"test_list_shows_a_folder_whose_status_file_is_#{label.tr(" ", "_")}") do
      home = fresh_home
      folder(home, STOPPED, status_text: text)
      result = list_call(home, "--store", "alpha")

      assert_equal 0, result.code
      assert_includes result.out, "unknown"
    end
  end

  UNREAL.each do |name|
    define_method(:"test_older_than_leaves_the_folder_#{name}_and_exits_0") do
      home = fresh_home
      folder(home, name)
      folder(home, STOPPED)
      result = purge_call(home, "--store", "alpha", "--older-than", "2027-01-01")

      assert_equal [0, [name]], [result.code, folder_names(home)]
    end

    define_method(:"test_interrupted_leaves_the_folder_#{name}") do
      home = fresh_home
      folder(home, name)
      result = purge_call(home, "--store", "alpha", "--interrupted", clock: NOW)

      assert_equal [0, [name]], [result.code, folder_names(home)]
    end

    define_method(:"test_list_shows_the_folder_#{name}_without_crashing") do
      home = fresh_home
      folder(home, name)
      result = list_call(home, "--store", "alpha")

      assert_equal 0, result.code
      assert_includes result.out, name
    end
  end
end
