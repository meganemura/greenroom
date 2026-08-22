# frozen_string_literal: true

require "test_helper"
require "greenroom/census/job"

class Greenroom::Census::JobTest < Minitest::Test
  include Greenroom::ResetsGlobalState

  class SubclassJob < Greenroom::Census::Job
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
