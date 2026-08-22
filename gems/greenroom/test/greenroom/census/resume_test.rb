# frozen_string_literal: true

require "test_helper"
require "greenroom/census/cursor"

# An interruption and resume, driven by hand instead of through Sidekiq
# (which needs Redis for `perform`; see `census/job_test.rb`). This proves
# the actual guarantee `Cursor` exists for: that splitting a run into two
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

  def rows
    (1..10).to_a
  end

  # Mimics a Sidekiq `array_enumerator`: yields `[item, index]` pairs, and
  # can resume from a given offset -- the shape `Cursor.decorate` expects to
  # wrap.
  def array_enumerator(array, cursor:)
    array.each_with_index.drop(cursor || 0).to_enum
  end

  def run_segment(cursor:, stop_after:)
    recorder = Greenroom::Recorder.new(run_id: "r1", experiment: "resume-test")
    position, counts = Greenroom::Census::Cursor.split(cursor)
    recorder.restore(counts) if counts

    run = Greenroom::Census::Run.new(
      target: CountingTarget.new,
      recorder: recorder,
      reader: Greenroom::Census::Reader::Direct.new
    )

    decorated = Greenroom::Census::Cursor.decorate(array_enumerator(rows, cursor: position), recorder)

    last_cursor = cursor
    Greenroom::Recorder.install(recorder)
    begin
      decorated.each_with_index do |(row, row_cursor), i|
        run.visit(row)
        last_cursor = row_cursor
        break if stop_after && i + 1 == stop_after
      end
    ensure
      Greenroom::Recorder.uninstall
    end

    [recorder, last_cursor]
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
