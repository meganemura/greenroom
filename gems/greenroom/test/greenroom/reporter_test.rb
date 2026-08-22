# frozen_string_literal: true

require "test_helper"

class Greenroom::ReporterTest < Minitest::Test
  def test_record_is_abstract
    assert_raises(NotImplementedError) { Greenroom::Reporter.new.record("Event", {}) }
  end
end

class Greenroom::Reporter::NullTest < Minitest::Test
  def test_record_does_nothing_and_returns_without_raising
    reporter = Greenroom::Reporter::Null.new

    reporter.record("Event", {value: "x" * 300})
  end
end

class Greenroom::Reporter::MemoryTest < Minitest::Test
  def test_record_appends_to_events
    reporter = Greenroom::Reporter::Memory.new

    reporter.record("GreenroomCensus", {run_id: "abc", rows_scanned: 3})

    assert_equal 1, reporter.events.size
    assert_equal "GreenroomCensus", reporter.events.first.type
    assert_equal({run_id: "abc", rows_scanned: 3}, reporter.events.first.attributes)
  end

  def test_record_truncates_string_attribute_values
    long_value = "x" * 300
    reporter = Greenroom::Reporter::Memory.new

    reporter.record("Event", {value: long_value})

    assert_equal 255, reporter.events.first.attributes[:value].length
  end

  def test_record_does_not_truncate_non_string_values
    reporter = Greenroom::Reporter::Memory.new

    reporter.record("Event", {count: 12_345})

    assert_equal 12_345, reporter.events.first.attributes[:count]
  end

  def test_events_accumulate_across_multiple_records
    reporter = Greenroom::Reporter::Memory.new

    reporter.record("A", {})
    reporter.record("B", {})

    assert_equal %w[A B], reporter.events.map(&:type)
  end
end
