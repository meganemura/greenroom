# frozen_string_literal: true

require "scientist"

require_relative "greenroom/version"
require_relative "greenroom/digest"
require_relative "greenroom/reporter"
require_relative "greenroom/recorder"
require_relative "greenroom/experiment_behavior"
require_relative "greenroom/census/run"

module Greenroom
  class Error < StandardError; end

  # Raised by `assert_registered!` when no host class has claimed
  # `Scientist::Experiment`'s one registration slot yet.
  class NotRegisteredError < Error; end

  # Raised by `Census::Job#build_enumerator` when the host's Sidekiq server
  # middleware chain does not include `Census::Middleware` yet. Without that
  # middleware, an error escaping `each_iteration` leaves the thread-local
  # recorder installed (Sidekiq skips `on_stop` in that case), and the next,
  # unrelated job Sidekiq happens to run on the same thread would find an
  # experiment already turned on. Checking at the start of every run turns
  # that silent leak into a startup-time failure instead.
  #
  # Defined here, alongside `NotRegisteredError`, rather than in
  # `census/middleware.rb`: this file is the one place that never requires
  # Sidekiq, so every error this gem can raise stays nameable and
  # rescuable from `require "greenroom"` alone, without also pulling in
  # the census machinery.
  class MiddlewareNotRegisteredError < Error; end

  class << self
    # Where recorded events go. Defaults to `Reporter::Null`, so a host that
    # has not configured delivery yet gets silence instead of a load-time
    # error.
    attr_accessor :reporter

    # Meant to run at boot. A host that includes only `ExperimentBehavior`
    # in its experiment class, and forgets `Scientist::Experiment`, gets no
    # error and no candidate ever runs: `enabled?` and `publish` both exist,
    # but `Scientist::Experiment.new` still returns a `Scientist::Default`
    # (`enabled?` always false), so every experiment stays quietly inert
    # forever. Probing at boot turns that silent misconfiguration into a
    # startup failure instead.
    def assert_registered!
      return unless Scientist::Experiment.new("greenroom-probe").instance_of?(Scientist::Default)

      raise NotRegisteredError,
        "No class includes Scientist::Experiment yet. Add `include Scientist::Experiment` " \
        "to the class that runs your experiments."
    end
  end

  self.reporter = Reporter::Null.new
end
