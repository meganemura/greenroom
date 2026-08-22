# frozen_string_literal: true

module Greenroom
  # The seam between the parts of this gem that produce events (the recorder,
  # the experiment behavior) and wherever those events actually go. Kept as
  # an abstract base plus two concrete subclasses here, and any real delivery
  # implementation in its own file, so the core of the gem never has to load
  # a delivery library it does not use.
  class Reporter
    # Greenroom's own bound, chosen rather than mirrored. Measured against
    # the New Relic Ruby agent at version 10.7.1, that agent truncates an
    # attribute name at 255 characters and an attribute value at 4095, so
    # this cap is stricter than the value limit of the one delivery target
    # written so far.
    #
    # It is stricter on purpose. Every attribute this gem sends is meant to
    # be short: a digest, a class name, a count, an identifier. A string
    # long enough to reach this cap is a sign that something a host supplied
    # -- an experiment name, a row identifier -- is carrying more than a
    # label, and cutting it keeps one such value from bloating every event
    # of a run.
    MAX_ATTRIBUTE_LENGTH = 255

    def record(event_type, attributes)
      raise NotImplementedError, "#{self.class} must implement #record"
    end

    private

    def truncate(attributes)
      attributes.transform_values do |value|
        value.is_a?(String) ? value[0, MAX_ATTRIBUTE_LENGTH] : value
      end
    end
  end

  # The default reporter. A host that never configures `Greenroom.reporter`
  # gets silence rather than a NotImplementedError, so requiring this gem
  # alone never breaks a caller that has not wired up delivery yet.
  class Reporter::Null < Reporter
    def record(event_type, attributes)
    end
  end

  # Accumulates every recorded event in memory instead of sending it
  # anywhere. Exists for tests: a spec can install this reporter and then
  # assert on `#events` instead of stubbing a real delivery library.
  class Reporter::Memory < Reporter
    Event = Struct.new(:type, :attributes)

    attr_reader :events

    def initialize
      @events = []
    end

    def record(event_type, attributes)
      @events << Event.new(event_type, truncate(attributes))
    end
  end
end
