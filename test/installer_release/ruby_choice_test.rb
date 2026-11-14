# frozen_string_literal: true

require_relative "release_helper"

class InstallerReleaseRubyChoiceTest < Minitest::Test
  include ReleaseHelper

  def test_the_bundle_program_sits_beside_the_ruby
    assert_equal "/r/bin/bundle", InstallerRelease::Ruby.new("/r/bin/ruby").bundle
  end

  def test_takes_the_developer_ruby_first
    assert_equal "/dev/ruby", InstallerRelease::RubyChoice.new(override: "/dev/ruby").call({}).path
  end

  def test_keeps_the_running_ruby_when_no_developer_ruby_is_named
    assert_equal RbConfig.ruby, InstallerRelease::RubyChoice.new.call({}).path
  end
end
