# frozen_string_literal: true

require_relative "digest"

module Greenroom
  # The tallying half of a census run. A census job installs one of these on
  # the thread it is running on; while it is installed, `enabled?` is true
  # and comparisons flow into it instead of going nowhere. Uninstalling it
  # turns comparisons back off, so the presence of a recorder is the one
  # mechanism behind both "is the experiment running" and "where do the
  # results go".
  class Recorder
    # A mutable set of counters for one experiment name. Kept separate from
    # `Recorder` itself because a single run can, in principle, touch more
    # than one experiment name (a misconfigured target, or a host that reuses
    # one job for several experiments), and each needs its own counts.
    class Tally
      attr_accessor :comparisons, :mismatches, :ignored, :candidate_errors, :control_errors

      def initialize
        @comparisons = 0
        @mismatches = 0
        @ignored = 0
        @candidate_errors = 0
        @control_errors = 0
      end

      # String keys, not symbols: a Tally's hash only ever leaves this class
      # inside `Recorder#snapshot`, and that Hash must already be shaped like
      # JSON, because it travels through `Sidekiq.dump_json` / `load_json`
      # (which always returns string keys) on the way to and from a cursor.
      def to_h
        {
          "comparisons" => comparisons,
          "mismatches" => mismatches,
          "ignored" => ignored,
          "candidate_errors" => candidate_errors,
          "control_errors" => control_errors
        }
      end
    end

    # census jobs process one row per thread, so the thread is the unit a
    # recorder must be scoped to: `Thread.current` (fiber-local by default)
    # gives each thread its own slot without one thread's recorder leaking
    # into a concurrently running, unrelated job on another thread.
    THREAD_KEY = :greenroom_recorder
    private_constant :THREAD_KEY

    class << self
      def current
        Thread.current[THREAD_KEY]
      end

      def install(recorder)
        Thread.current[THREAD_KEY] = recorder
      end

      # Returns the recorder that was installed, so a caller that wants to
      # flush it (`on_stop`) does not need to have held onto a reference
      # itself.
      def uninstall
        recorder = Thread.current[THREAD_KEY]
        Thread.current[THREAD_KEY] = nil
        recorder
      end

      # For tests and any plain call site that wants a recorder installed
      # for the duration of a block. `ensure` uninstalls even if the block
      # raises, so a failing test cannot leave a recorder behind for the
      # next one.
      def with(recorder)
        install(recorder)
        yield
      ensure
        uninstall
      end
    end

    attr_reader :run_id, :sample_limit, :rows_scanned, :tallies, :samples
    attr_accessor :subject

    def initialize(run_id:, experiment: nil, sample_limit: 100)
      @run_id = run_id
      @sample_limit = sample_limit
      @rows_scanned = 0
      @row_errors = 0
      @tallies = {}
      @samples = []
      @subject = nil

      # A run that never triggers a single comparison (a module-only
      # include, or a target whose `call` never reaches `Scientist.run`)
      # would otherwise leave `tallies` empty and `flush_total` silent. A
      # silent run and a run that never started look identical from the
      # outside, so the zero must be sent, not inferred from an absence.
      tally_for(experiment) if experiment
    end

    def count_row
      @rows_scanned += 1
    end

    def record_row_error(_error)
      @row_errors += 1
    end

    # Receives a `Scientist::Result` from `publish`. Counts are split into
    # "mismatched" and "ignored" so that a host's `ignore` block, which
    # exists to suppress noisy known-differences, does not also hide how
    # much it is suppressing.
    def record(result)
      tally = tally_for(result.experiment_name)
      tally.comparisons += 1
      tally.mismatches += 1 if result.mismatched?
      tally.ignored += 1 if result.ignored?
      tally.candidate_errors += result.candidates.count(&:raised?)
      tally.control_errors += 1 if result.control&.raised?

      sample(result) if result.mismatched?
    end

    def snapshot
      {
        "rows_scanned" => @rows_scanned,
        "row_errors" => @row_errors,
        "tallies" => @tallies.transform_values(&:to_h)
      }
    end

    def restore(snapshot)
      @rows_scanned = snapshot.fetch("rows_scanned", 0).to_i
      @row_errors = snapshot.fetch("row_errors", 0).to_i
      @tallies = {}
      snapshot.fetch("tallies", {}).each do |name, counts|
        tally = tally_for(name)
        tally.comparisons = counts.fetch("comparisons", 0).to_i
        tally.mismatches = counts.fetch("mismatches", 0).to_i
        tally.ignored = counts.fetch("ignored", 0).to_i
        tally.candidate_errors = counts.fetch("candidate_errors", 0).to_i
        tally.control_errors = counts.fetch("control_errors", 0).to_i
      end
    end

    # Sends one progress event (this run is alive, with the counts so far)
    # and one mismatch event per sample gathered since the last flush. The
    # samples that were just sent are discarded afterward: a sample is
    # evidence, not part of the denominator, so re-sending it on resume
    # (see `Census::Cursor`) is harmless, and keeping it around forever
    # would only grow memory for no benefit.
    def flush_segment(reporter)
      emit(reporter, "GreenroomCensusProgress")
      @samples.each { |sample| reporter.record("GreenroomMismatch", sample) }
      @samples.clear
    end

    # Sends the run's aggregate event: the one number a judge reads as the
    # denominator. Splitting counts across `flush_segment` calls and asking
    # a judge to sum them would make that sum itself something to verify for
    # double-counting or gaps; a single event at the end avoids that.
    def flush_total(reporter)
      emit(reporter, "GreenroomCensus")
    end

    private

    def tally_for(name)
      @tallies[name] ||= Tally.new
    end

    def sample(result)
      return if @samples.size >= @sample_limit

      candidate = result.mismatched.first
      @samples << {
        run_id: run_id,
        experiment: result.experiment_name,
        subject: subject,
        control_digest: Digest.of(result.control&.cleaned_value),
        candidate_digest: Digest.of(candidate&.cleaned_value),
        control_error: error_class_name(result.control),
        candidate_error: error_class_name(candidate)
      }
    end

    def error_class_name(observation)
      observation.exception.class.name if observation&.raised?
    end

    # Shared by `flush_segment` and `flush_total`: both send one event per
    # experiment tallied, plus the run-wide `rows_scanned` and `row_errors`.
    # When no comparison has run yet, `tallies` is empty; a run that is
    # merely quiet still needs one event (see the comment in `initialize`),
    # so this falls back to a single zero tally keyed by `nil`.
    def emit(reporter, event_type)
      entries = @tallies.empty? ? {nil => Tally.new} : @tallies
      entries.each do |name, tally|
        reporter.record(event_type, {
          run_id: run_id,
          experiment: name,
          rows_scanned: rows_scanned,
          comparisons: tally.comparisons,
          mismatches: tally.mismatches,
          ignored: tally.ignored,
          candidate_errors: tally.candidate_errors,
          control_errors: tally.control_errors,
          row_errors: @row_errors
        })
      end
    end
  end
end
