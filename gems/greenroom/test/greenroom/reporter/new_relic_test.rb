# frozen_string_literal: true

require "test_helper"
require "greenroom/reporter/new_relic"

# A minimal double for the one New Relic agent call this adapter makes.
# Standing in for the real `newrelic_rpm` gem, which is not a dependency of
# this gem (see greenroom.gemspec): a host wires this file to its own,
# already-loaded agent. This double only checks that the adapter calls the
# interface correctly, not that a message actually reaches New Relic.
module NewRelic
  module Agent
    class << self
      attr_reader :recorded_events

      def record_custom_event(event_type, attributes)
        (@recorded_events ||= []) << [event_type, attributes]
      end

      def reset!
        @recorded_events = []
      end
    end
  end
end

class Greenroom::Reporter::NewRelicTest < Minitest::Test
  def setup
    NewRelic::Agent.reset!
  end

  def test_record_calls_new_relic_agent_record_custom_event
    reporter = Greenroom::Reporter::NewRelic.new

    reporter.record("GreenroomCensus", {run_id: "abc"})

    assert_equal [["GreenroomCensus", {run_id: "abc"}]], NewRelic::Agent.recorded_events
  end

  def test_record_truncates_string_attribute_values_before_sending
    reporter = Greenroom::Reporter::NewRelic.new

    reporter.record("GreenroomCensus", {value: "x" * 300})

    _, attributes = NewRelic::Agent.recorded_events.first
    assert_equal 255, attributes[:value].length
  end
end
