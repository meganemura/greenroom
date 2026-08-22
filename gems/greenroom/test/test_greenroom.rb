# frozen_string_literal: true

require "test_helper"

class TestGreenroom < Minitest::Test
  def test_it_has_a_version_number
    refute_nil ::Greenroom::VERSION
  end
end
