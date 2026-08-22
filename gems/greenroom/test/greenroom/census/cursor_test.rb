# frozen_string_literal: true

require "test_helper"
require "json"
require "greenroom/census/cursor"

class Greenroom::Census::CursorTest < Minitest::Test
  def test_split_returns_nil_position_and_nil_counts_for_a_nil_cursor
    assert_equal [nil, nil], Greenroom::Census::Cursor.split(nil)
  end

  def test_split_returns_the_position_and_counts_from_a_cursor
    cursor = {"position" => 4, "counts" => {"rows_scanned" => 4}}

    assert_equal [4, {"rows_scanned" => 4}], Greenroom::Census::Cursor.split(cursor)
  end

  def test_decorate_yields_the_original_object_paired_with_position_and_counts
    recorder = Greenroom::Recorder.new(run_id: "r1")
    source = [["a", 0], ["b", 1]].each
    decorated = Greenroom::Census::Cursor.decorate(source, recorder)

    first_object, first_cursor = decorated.next
    assert_equal "a", first_object
    assert_equal 0, first_cursor["position"]
    assert_equal recorder.snapshot, first_cursor["counts"]
  end

  def test_decorate_reads_the_recorder_snapshot_at_yield_time_not_up_front
    # `decorate` must be lazy: if it eagerly built every cursor before
    # `each_iteration` ran, every row would carry the same (initial) counts,
    # and a resume from any of them would replay every row already
    # processed in this segment.
    recorder = Greenroom::Recorder.new(run_id: "r1")
    source = [["a", 0], ["b", 1], ["c", 2]].each
    decorated = Greenroom::Census::Cursor.decorate(source, recorder)

    _, first_cursor = decorated.next
    assert_equal 0, first_cursor["counts"]["rows_scanned"]

    recorder.count_row
    recorder.count_row

    _, second_cursor = decorated.next
    assert_equal 2, second_cursor["counts"]["rows_scanned"]
  end

  def test_split_and_decorate_round_trip_through_json
    recorder = Greenroom::Recorder.new(run_id: "r1", experiment: "price-v2")
    recorder.count_row
    source = [["a", 5]].each
    decorated = Greenroom::Census::Cursor.decorate(source, recorder)
    _, cursor = decorated.next

    round_tripped = JSON.parse(JSON.generate(cursor))
    position, counts = Greenroom::Census::Cursor.split(round_tripped)

    assert_equal 5, position
    restored = Greenroom::Recorder.new(run_id: "r1")
    restored.restore(counts)
    assert_equal recorder.rows_scanned, restored.rows_scanned
  end
end
