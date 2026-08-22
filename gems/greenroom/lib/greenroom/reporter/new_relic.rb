# frozen_string_literal: true

require "greenroom/reporter"

module Greenroom
  # Sends recorded events to New Relic as custom events. Not required by
  # `greenroom.rb`: a host that wants this delivery requires this file on
  # purpose, after loading its own New Relic agent, so the gem's own runtime
  # dependencies never include the agent gem.
  class Reporter::NewRelic < Reporter
    def record(event_type, attributes)
      ::NewRelic::Agent.record_custom_event(event_type, truncate(attributes))
    end
  end
end
