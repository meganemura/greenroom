# frozen_string_literal: true

require "test_helper"

class Greenroom::Census::Reader::DirectTest < Minitest::Test
  def test_call_runs_the_block_and_returns_its_value
    reader = Greenroom::Census::Reader::Direct.new

    result = reader.call { 1 + 1 }

    assert_equal 2, result
  end
end

class Greenroom::Census::RunTest < Minitest::Test
  RowWithId = Struct.new(:id)

  class RecordingTarget
    attr_reader :visited

    def initialize
      @visited = []
    end

    def experiment
      "test"
    end

    def call(row)
      @visited << row
    end
  end

  class FreezeCheckingTarget
    attr_reader :seen_frozen

    def call(row)
      @seen_frozen = row.frozen?
    end
  end

  class RaisingOnBadRowTarget
    def call(row)
      raise "boom" if row == :bad

      row
    end
  end

  class CountingReader
    attr_reader :call_count

    def initialize
      @call_count = 0
    end

    def call
      @call_count += 1
      yield
    end
  end

  def build_run(target, recorder, reader: Greenroom::Census::Reader::Direct.new)
    Greenroom::Census::Run.new(target: target, recorder: recorder, reader: reader)
  end

  def test_visit_counts_the_row_and_calls_the_target
    target = RecordingTarget.new
    recorder = Greenroom::Recorder.new(run_id: "r1")
    run = build_run(target, recorder)

    run.visit(RowWithId.new(1))

    assert_equal 1, recorder.rows_scanned
    assert_equal [RowWithId.new(1)], target.visited
  end

  def test_visit_freezes_the_row_before_calling_the_target
    target = FreezeCheckingTarget.new
    recorder = Greenroom::Recorder.new(run_id: "r1")
    run = build_run(target, recorder)

    run.visit(RowWithId.new(1))

    assert target.seen_frozen
  end

  def test_visit_sets_the_recorder_subject_from_the_row_id
    target = RecordingTarget.new
    recorder = Greenroom::Recorder.new(run_id: "r1")
    run = build_run(target, recorder)

    run.visit(RowWithId.new(7))

    assert_equal 7, recorder.subject
  end

  def test_visit_sets_the_recorder_subject_to_nil_when_the_row_has_no_id
    target = RecordingTarget.new
    recorder = Greenroom::Recorder.new(run_id: "r1")
    run = build_run(target, recorder)

    run.visit(Object.new)

    assert_nil recorder.subject
  end

  def test_visit_rescues_a_raising_row_and_records_a_row_error_then_continues
    target = RaisingOnBadRowTarget.new
    recorder = Greenroom::Recorder.new(run_id: "r1")
    run = build_run(target, recorder)

    run.visit(:bad)
    run.visit(:good)

    reporter = Greenroom::Reporter::Memory.new
    recorder.flush_total(reporter)
    census = reporter.events.find { |event| event.type == "GreenroomCensus" }

    assert_equal 2, census.attributes[:rows_scanned]
    assert_equal 1, census.attributes[:row_errors]
  end

  def test_visit_reads_through_the_given_reader
    target = RecordingTarget.new
    recorder = Greenroom::Recorder.new(run_id: "r1")
    reader = CountingReader.new
    run = build_run(target, recorder, reader: reader)

    run.visit(RowWithId.new(1))

    assert_equal 1, reader.call_count
  end
end
