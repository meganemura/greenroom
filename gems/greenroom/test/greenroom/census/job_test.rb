# frozen_string_literal: true

require "test_helper"
require "greenroom/census/job"
require "greenroom/census/middleware"

class Greenroom::Census::JobTest < Minitest::Test
  include Greenroom::ResetsGlobalState

  class SubclassJob < Greenroom::Census::Job
  end

  # Registers `Census::Middleware` on Sidekiq's real, process-wide server
  # chain for the duration of the block, then removes it -- `add`/`remove`
  # are the only interface `Sidekiq::Middleware::Chain` offers, and this
  # chain is shared by every test in the process, so a test that registers
  # the middleware must also be the one that unregisters it.
  def with_middleware_registered
    Sidekiq.default_configuration.server_middleware { |chain| chain.add Greenroom::Census::Middleware }
    yield
  ensure
    Sidekiq.default_configuration.server_middleware { |chain| chain.remove Greenroom::Census::Middleware }
  end

  # A target and a `Job` subclass for the `build_enumerator` tests below.
  # `row_enumerator` is overridden with `array_enumerator` (an in-memory
  # Sidekiq helper) rather than the default `active_record_records_enumerator`,
  # so these tests need no ActiveRecord dependency (see the README's note
  # on `row_enumerator`).
  class RowEnumeratorTarget
    ROWS = [:a, :b, :c].freeze

    attr_reader :experiment

    def initialize(experiment: "row-enum-test")
      @experiment = experiment
    end
  end

  class RowEnumeratorJob < Greenroom::Census::Job
    def target(*)
      RowEnumeratorTarget.new
    end

    def row_enumerator(*, cursor:)
      array_enumerator(RowEnumeratorTarget::ROWS, cursor: cursor)
    end
  end

  # A `row_enumerator` that fails loudly if it ever runs, for the test that
  # proves `build_enumerator` raises before reading a single row when the
  # middleware guard fails -- rather than inferring "no row was read" from
  # the absence of some other effect, this makes reading a row impossible
  # to miss.
  class UnreachableRowEnumeratorJob < Greenroom::Census::Job
    def target(*)
      RowEnumeratorTarget.new(experiment: "unreachable-test")
    end

    def row_enumerator(*, cursor:)
      raise "row_enumerator must not run when the middleware guard fails"
    end
  end

  def test_reader_defaults_to_reader_direct
    job = SubclassJob.new

    assert_instance_of Greenroom::Census::Reader::Direct, job.reader
  end

  def test_each_iteration_visits_the_row_through_the_run
    job = SubclassJob.new
    visited = []
    run = Object.new
    run.define_singleton_method(:visit) { |row| visited << row }
    job.instance_variable_set(:@run, run)

    job.each_iteration(:a_row, "arg")

    assert_equal [:a_row], visited
  end

  def test_on_stop_flushes_the_segment_and_uninstalls_the_recorder
    job = SubclassJob.new
    reporter = Greenroom::Reporter::Memory.new
    Greenroom.reporter = reporter
    recorder = Greenroom::Recorder.new(run_id: "r1", experiment: "test")
    job.instance_variable_set(:@recorder, recorder)
    Greenroom::Recorder.install(recorder)

    job.on_stop

    assert_includes reporter.events.map(&:type), "GreenroomCensusProgress"
    assert_nil Greenroom::Recorder.current
  end

  def test_on_complete_flushes_the_total_using_the_instance_variable_not_the_thread_local
    # Sidekiq calls `on_stop` before `on_complete`, and `on_stop` uninstalls
    # the thread-local -- `on_complete` must still be able to send the run's
    # aggregate event after that, which is only possible by reading
    # `@recorder` rather than `Recorder.current`.
    job = SubclassJob.new
    reporter = Greenroom::Reporter::Memory.new
    Greenroom.reporter = reporter
    recorder = Greenroom::Recorder.new(run_id: "r1", experiment: "test")
    job.instance_variable_set(:@recorder, recorder)

    assert_nil Greenroom::Recorder.current

    job.on_complete

    assert_includes reporter.events.map(&:type), "GreenroomCensus"
  end

  def test_build_enumerator_installs_the_recorder_and_wraps_rows_with_a_cursor
    with_middleware_registered do
      job = RowEnumeratorJob.new
      job.jid = "run-1"

      enumerator = job.build_enumerator(cursor: nil)

      assert_instance_of Enumerator, enumerator
      assert_same job.instance_variable_get(:@recorder), Greenroom::Recorder.current
      assert_equal "run-1", Greenroom::Recorder.current.run_id

      row, cursor = enumerator.first
      assert_equal :a, row
      assert_equal 0, cursor["position"]
      assert_equal Greenroom::Recorder.current.snapshot, cursor["counts"]
    end
  end

  def test_build_enumerator_restores_counts_and_resumes_from_the_cursor_position
    resumed_counts = {
      "rows_scanned" => 5,
      "row_errors" => 0,
      "tallies" => {"row-enum-test" => {
        "comparisons" => 5, "mismatches" => 0, "ignored" => 0,
        "candidate_errors" => 0, "control_errors" => 0
      }}
    }

    with_middleware_registered do
      job = RowEnumeratorJob.new
      job.jid = "run-2"

      enumerator = job.build_enumerator(cursor: {"position" => 1, "counts" => resumed_counts})

      recorder = job.instance_variable_get(:@recorder)
      assert_equal 5, recorder.rows_scanned
      assert_equal 5, recorder.tallies.fetch("row-enum-test").comparisons

      row, = enumerator.first
      assert_equal :b, row
    end
  end

  def test_build_enumerator_raises_when_the_middleware_is_not_registered_and_reads_no_rows
    job = UnreachableRowEnumeratorJob.new
    job.jid = "run-3"

    error = assert_raises(Greenroom::MiddlewareNotRegisteredError) do
      job.build_enumerator(cursor: nil)
    end

    assert_match(/Census::Middleware/, error.message)
  end

  def test_build_enumerator_reads_when_the_middleware_is_registered
    with_middleware_registered do
      job = RowEnumeratorJob.new
      job.jid = "run-4"

      enumerator = job.build_enumerator(cursor: nil)
      row, = enumerator.first

      assert_equal :a, row
    end
  end

  # An experiment class for `test_the_full_hook_sequence_...` below, real
  # enough that `Scientist.run` drives `ExperimentBehavior#publish` into
  # whatever recorder `build_enumerator` installed.
  class HookFlowExperiment
    include Scientist::Experiment
    include Greenroom::ExperimentBehavior

    attr_reader :name

    def initialize(name)
      @name = name
    end
  end

  class HookFlowTarget
    ROWS = [1, 2, 3].freeze

    def experiment
      "job-flow-test"
    end

    def call(row)
      Scientist.run("job-flow-test") do |e|
        e.use { row }
        e.try { row }
      end
    end
  end

  class HookFlowJob < Greenroom::Census::Job
    def target(*)
      HookFlowTarget.new
    end

    def row_enumerator(*, cursor:)
      array_enumerator(HookFlowTarget::ROWS, cursor: cursor)
    end
  end

  def test_the_full_hook_sequence_from_build_enumerator_through_on_complete_reports_the_run
    # Drives the same sequence Sidekiq drives from `perform`
    # (`build_enumerator`, then `each_iteration` per row, then `on_stop`,
    # then `on_complete`), but by hand: calling `perform` itself needs
    # Redis, which this suite does not run against (see the other tests in
    # this file).
    Scientist::Experiment.set_default(HookFlowExperiment)
    reporter = Greenroom::Reporter::Memory.new
    Greenroom.reporter = reporter

    with_middleware_registered do
      job = HookFlowJob.new
      job.jid = "flow-1"

      enumerator = job.build_enumerator(cursor: nil)
      enumerator.each { |row, _cursor| job.each_iteration(row) }
      job.on_stop
      job.on_complete
    end

    assert_includes reporter.events.map(&:type), "GreenroomCensusProgress"
    census_event = reporter.events.find { |event| event.type == "GreenroomCensus" }
    refute_nil census_event
    assert_equal "flow-1", census_event.attributes[:run_id]
    assert_equal "job-flow-test", census_event.attributes[:experiment]
    assert_equal 3, census_event.attributes[:rows_scanned]
    assert_equal 3, census_event.attributes[:comparisons]
  end

  def test_a_subclass_may_not_define_perform
    # Sidekiq's `Sidekiq::Job::Iterable::ClassMethods#method_added` raises
    # the moment a `perform` method is defined on an iterable job class --
    # `perform` is Sidekiq's own hook for driving the iteration, and an
    # iterable job must not replace it.
    error = assert_raises(RuntimeError) do
      Class.new(Greenroom::Census::Job) do
        def perform
        end
      end
    end

    assert_match(/must not define #perform/, error.message)
  end
end
