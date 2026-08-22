# frozen_string_literal: true

require "test_helper"

class Greenroom::AssertRegisteredTest < Minitest::Test
  include Greenroom::ResetsGlobalState

  def test_raises_before_any_class_registers_with_scientist_experiment
    Scientist::Experiment.set_default(Scientist::Default)

    assert_raises(Greenroom::NotRegisteredError) { Greenroom.assert_registered! }
  end

  def test_does_not_raise_after_a_class_registers_with_scientist_experiment
    Class.new do
      include Scientist::Experiment

      def initialize(name)
      end
    end

    Greenroom.assert_registered!
  end

  def test_the_error_message_tells_the_host_how_to_fix_it
    Scientist::Experiment.set_default(Scientist::Default)

    error = assert_raises(Greenroom::NotRegisteredError) { Greenroom.assert_registered! }

    assert_match(/include Scientist::Experiment/, error.message)
  end
end

class Greenroom::ReporterAccessorTest < Minitest::Test
  include Greenroom::ResetsGlobalState

  def test_reporter_defaults_to_a_null_reporter
    assert_instance_of Greenroom::Reporter::Null, Greenroom.reporter
  end

  def test_reporter_can_be_replaced
    memory = Greenroom::Reporter::Memory.new

    Greenroom.reporter = memory

    assert_same memory, Greenroom.reporter
  end
end
