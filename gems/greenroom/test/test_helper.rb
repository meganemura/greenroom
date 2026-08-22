# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "greenroom"
require "scientist"

require "minitest/autorun"

module Greenroom
  # A test that registers a class with `Scientist::Experiment`, installs a
  # `Recorder`, or swaps `Greenroom.reporter` changes process-wide state.
  # `Scientist::Experiment.set_default` in particular has exactly one slot
  # for the whole process, so a test that does not restore it leaks into
  # every test that runs after it. Include this and every test in the class
  # gets the save-and-restore for free.
  module ResetsGlobalState
    def setup
      super
      @greenroom_saved_experiment_klass =
        Scientist::Experiment.instance_variable_get(:@experiment_klass)
    end

    def teardown
      Scientist::Experiment.set_default(@greenroom_saved_experiment_klass)
      Greenroom::Recorder.uninstall
      Greenroom.reporter = Greenroom::Reporter::Null.new
      super
    end
  end
end
