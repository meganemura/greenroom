# frozen_string_literal: true

module Greenroom
  # The two behaviours `Scientist::Experiment` requires from its includer,
  # plus a non-raising override of `raised`.
  #
  # A module, not a concrete class: `Scientist::Experiment` has exactly one
  # registration slot per process (`Scientist::Experiment.set_default`), and
  # a later `include` silently steals it from an earlier one. If this gem
  # shipped a class for a host to include, requiring this gem at all would
  # risk taking over that slot from the host's own experiment class. A host
  # includes both `Scientist::Experiment` and this module into its own
  # class instead, keeping the registration decision with the host.
  #
  # A host that wants an experiment to run outside a census (for example,
  # sampling live traffic) overrides `enabled?` in its own class; that is
  # why `publish` still works when no recorder is installed.
  module ExperimentBehavior
    # True exactly while a census job has a recorder installed on this
    # thread. The recorder's presence is what turns an experiment on, so
    # there is only one mechanism to reason about, not two that could drift
    # out of sync.
    def enabled?
      !Recorder.current.nil?
    end

    # A recorder installed on this thread means a census is in progress:
    # hand it the result to tally instead of sending an event per
    # comparison. With no recorder installed, an experiment that a host
    # enabled outside a census (see the module documentation) still gets a
    # single event per comparison, sent directly.
    def publish(result)
      recorder = Recorder.current
      if recorder
        recorder.record(result)
      else
        publish_comparison(result)
      end
    end

    # Scientist's default `raised` re-raises, which would let a failure in
    # this gem's own instrumentation (a bad `clean` block, a reporter
    # outage) break the host's actual call. Recording the failure and
    # returning nil keeps that failure from ever reaching the caller.
    def raised(operation, error)
      begin
        Greenroom.reporter.record("GreenroomInternalError", {
          experiment: name,
          operation: operation,
          error: error.class.name
        })
      rescue
        # Recording the failure must never itself fail the call that
        # triggered it -- a reporter outage would otherwise take down the
        # very requests this gem exists to observe, in a way that a broken
        # bit of measurement code has no business doing.
      end
      nil
    end

    private

    def publish_comparison(result)
      candidate = result.candidates.first
      Greenroom.reporter.record("GreenroomComparison", {
        experiment: result.experiment_name,
        matched: result.matched?,
        control_duration_ms: duration_ms(result.control),
        candidate_duration_ms: duration_ms(candidate),
        candidate_error: error_class_name(candidate)
      })
    end

    def duration_ms(observation)
      observation && observation.duration * 1000
    end

    def error_class_name(observation)
      observation.exception.class.name if observation&.raised?
    end
  end
end
