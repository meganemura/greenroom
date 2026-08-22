# frozen_string_literal: true

require "test_helper"
require "greenroom/census/job"
require "greenroom/census/middleware"

# An interruption and resume, driven through `Census::Job#build_enumerator`
# by hand instead of through Sidekiq (which needs Redis for `perform`; see
# `census/job_test.rb`). This proves the actual guarantee `Cursor` and
# `build_enumerator` exist for together: that splitting a run into two
# segments produces the same totals as running it as one, because each
# segment's `Recorder` starts from the counts attached to the cursor it
# resumed from rather than from zero.
class Greenroom::Census::ResumeTest < Minitest::Test
  include Greenroom::ResetsGlobalState

  class ResumeExperiment
    include Scientist::Experiment
    include Greenroom::ExperimentBehavior

    attr_reader :name

    def initialize(name)
      @name = name
    end
  end

  class CountingTarget
    ROWS = (1..10).to_a.freeze

    def experiment
      "resume-test"
    end

    def call(row)
      Scientist.run("resume-test") do |e|
        e.use { row }
        e.try { row }
      end
    end
  end

  class ResumeJob < Greenroom::Census::Job
    def target(*)
      CountingTarget.new
    end

    def row_enumerator(*, cursor:)
      array_enumerator(CountingTarget::ROWS, cursor: cursor)
    end
  end

  def setup
    super
    Sidekiq.default_configuration.server_middleware { |chain| chain.add Greenroom::Census::Middleware }
  end

  def teardown
    Sidekiq.default_configuration.server_middleware { |chain| chain.remove Greenroom::Census::Middleware }
    super
  end

  def run_segment(cursor:, stop_after:)
    job = ResumeJob.new
    job.jid = "r1"

    enumerator = job.build_enumerator(cursor: cursor)

    last_cursor = cursor
    begin
      enumerator.each_with_index do |(row, row_cursor), i|
        job.each_iteration(row)
        last_cursor = row_cursor
        break if stop_after && i + 1 == stop_after
      end
    ensure
      Greenroom::Recorder.uninstall
    end

    [job.instance_variable_get(:@recorder), last_cursor]
  end

  def test_a_run_interrupted_and_resumed_does_not_double_count_rows
    first_recorder, cursor_at_interruption = run_segment(cursor: nil, stop_after: 5)

    assert_equal 5, first_recorder.rows_scanned
    assert_equal 5, first_recorder.tallies.fetch("resume-test").comparisons

    second_recorder, = run_segment(cursor: cursor_at_interruption, stop_after: nil)

    assert_equal 10, second_recorder.rows_scanned
    assert_equal 10, second_recorder.tallies.fetch("resume-test").comparisons
  end

  def test_an_uninterrupted_run_produces_the_same_totals
    recorder, = run_segment(cursor: nil, stop_after: nil)

    assert_equal 10, recorder.rows_scanned
    assert_equal 10, recorder.tallies.fetch("resume-test").comparisons
  end
end
