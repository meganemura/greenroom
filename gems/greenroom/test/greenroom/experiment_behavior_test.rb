# frozen_string_literal: true

require "test_helper"

class Greenroom::ExperimentBehaviorTest < Minitest::Test
  include Greenroom::ResetsGlobalState

  # `Scientist::Experiment.included` only registers a *class* as the
  # process-wide default (`base.instance_of?(Class)`); a module include is a
  # silent no-op for registration. `ExperimentBehavior` is deliberately a
  # module for this same reason (see the design note in the module itself),
  # so exercising it means including it into a real host class, alongside
  # `Scientist::Experiment` -- in that order, so `ExperimentBehavior#raised`
  # sits earlier in the ancestor chain than `Scientist::Experiment#raised`
  # and actually overrides it, rather than the reverse.
  class RegisteredExperiment
    include Scientist::Experiment
    include Greenroom::ExperimentBehavior

    attr_reader :name

    def initialize(name)
      @name = name
    end
  end

  def test_including_experiment_behavior_alone_does_not_register_as_the_scientist_default
    # ExperimentBehavior on its own provides `enabled?` / `publish` /
    # `raised`, but not the registration hook -- that belongs to
    # `Scientist::Experiment.included`, which never runs unless a class
    # includes `Scientist::Experiment` itself. A class that includes only
    # `ExperimentBehavior` therefore can never seize the process's one
    # registration slot.
    klass = Class.new { include Greenroom::ExperimentBehavior }

    refute_kind_of klass, Scientist::Experiment.new("probe")
  end

  def test_enabled_is_false_with_no_recorder_installed
    experiment = RegisteredExperiment.new("test")

    refute experiment.enabled?
  end

  def test_enabled_is_true_while_a_recorder_is_installed
    experiment = RegisteredExperiment.new("test")
    recorder = Greenroom::Recorder.new(run_id: "r1")

    Greenroom::Recorder.with(recorder) do
      assert experiment.enabled?
    end
  end

  def test_candidate_only_runs_while_a_recorder_is_installed
    # Driven through `Scientist.run`, not direct instantiation: `Scientist.run`
    # is what a host actually calls, and it depends on `RegisteredExperiment`
    # being the process-wide default rather than on which class a test
    # happens to instantiate. `set_default` is made explicit here rather than
    # relied upon from this class's own `include Scientist::Experiment` at
    # load time, so the outcome does not depend on which test file loaded
    # last.
    Scientist::Experiment.set_default(RegisteredExperiment)

    ran_candidate = false
    Scientist.run("test") do |e|
      e.use { 1 }
      e.try { ran_candidate = true }
    end

    refute ran_candidate

    recorder = Greenroom::Recorder.new(run_id: "r1")
    Greenroom::Recorder.with(recorder) do
      Scientist.run("test") do |e|
        e.use { 1 }
        e.try { ran_candidate = true }
      end
    end

    assert ran_candidate
  end

  def test_publish_records_into_the_installed_recorder_instead_of_reporting_directly
    reporter = Greenroom::Reporter::Memory.new
    Greenroom.reporter = reporter
    recorder = Greenroom::Recorder.new(run_id: "r1")

    Greenroom::Recorder.with(recorder) do
      experiment = RegisteredExperiment.new("test")
      experiment.use { 1 }
      experiment.try { 1 }
      experiment.run
    end

    assert_equal 1, recorder.tallies.fetch("test").comparisons
    refute_includes reporter.events.map(&:type), "GreenroomComparison"
  end

  # A host that overrides `enabled?` to run outside a census (live sampling,
  # say) still needs `publish` to send somewhere when no recorder is
  # installed: `enabled?` from `ExperimentBehavior` alone would keep the
  # experiment off without a recorder, so this class stands in for that
  # host's override.
  class AlwaysEnabledExperiment < RegisteredExperiment
    def enabled?
      true
    end
  end

  def test_publish_sends_a_comparison_event_directly_when_no_recorder_is_installed
    reporter = Greenroom::Reporter::Memory.new
    Greenroom.reporter = reporter
    experiment = AlwaysEnabledExperiment.new("test")
    experiment.use { 1 }
    experiment.try { 2 }

    experiment.run

    comparison = reporter.events.find { |event| event.type == "GreenroomComparison" }
    refute_nil comparison
    assert_equal "test", comparison.attributes[:experiment]
    assert_equal false, comparison.attributes[:matched]
    assert_kind_of Numeric, comparison.attributes[:control_duration_ms]
    assert_kind_of Numeric, comparison.attributes[:candidate_duration_ms]
    assert_nil comparison.attributes[:candidate_error]
  end

  def test_comparison_event_carries_the_candidate_error_class_name
    reporter = Greenroom::Reporter::Memory.new
    Greenroom.reporter = reporter
    experiment = AlwaysEnabledExperiment.new("test")
    experiment.use { 1 }
    experiment.try { raise "boom" }

    experiment.run

    comparison = reporter.events.find { |event| event.type == "GreenroomComparison" }
    assert_equal "RuntimeError", comparison.attributes[:candidate_error]
  end

  def test_publish_raising_is_recorded_by_raised_and_never_reaches_the_caller
    # Scientist's own `run` wraps `publish(result)` in
    # `rescue StandardError => ex; raised :publish, ex; end`. This only
    # proves anything if `publish` itself does not also rescue -- it must
    # let the reporter's exception propagate so scientist's own rescue is
    # what invokes `raised`.
    failing_reporter = Object.new
    def failing_reporter.record(*)
      raise "reporter is down"
    end
    Greenroom.reporter = failing_reporter

    experiment = AlwaysEnabledExperiment.new("test")
    experiment.use { 42 }
    experiment.try { 42 }

    value = experiment.run

    assert_equal 42, value
  end

  def test_raised_reports_an_internal_error_event_without_the_exception_message
    reporter = Greenroom::Reporter::Memory.new
    Greenroom.reporter = reporter
    experiment = RegisteredExperiment.new("test")

    result = experiment.raised(:publish, RuntimeError.new("do not leak this"))

    assert_nil result
    event = reporter.events.find { |e| e.type == "GreenroomInternalError" }
    refute_nil event
    assert_equal "test", event.attributes[:experiment]
    assert_equal :publish, event.attributes[:operation]
    assert_equal "RuntimeError", event.attributes[:error]
    refute_includes event.attributes.values.map(&:to_s), "do not leak this"
  end

  def test_raised_swallows_a_reporter_failure_instead_of_raising
    failing_reporter = Object.new
    def failing_reporter.record(*)
      raise "reporter is down"
    end
    Greenroom.reporter = failing_reporter
    experiment = RegisteredExperiment.new("test")

    result = experiment.raised(:publish, RuntimeError.new("boom"))

    assert_nil result
  end
end
