# frozen_string_literal: true

# `sidekiq/iterable_job` alone leaves `Sidekiq::Job` (which supplies `jid`,
# among other things) only partially loaded; the full mixin this job needs
# requires `sidekiq` itself first.
require "sidekiq"
require "sidekiq/iterable_job"

require "greenroom/recorder"
require "greenroom/census/run"

module Greenroom
  module Census
    # A Sidekiq iterable job that turns a host's target (see `Census::Run`)
    # into a nightly census: a recorder is installed for exactly the
    # duration of one run, so the experiment it drives is on only inside
    # this job (see `ExperimentBehavior#enabled?`).
    #
    # A host subclasses this and defines `target(*args)`. This class does
    # not yet implement `build_enumerator`: that method must install a
    # `Recorder` keyed on `jid`, restore its counts from a resumed cursor,
    # and wrap the host's row source with `Census::Cursor.decorate` -- but
    # the interface a subclass should implement to supply that row source is
    # still undecided, so it is left out rather than guessed at here. A
    # subclass that wants to run today must implement `build_enumerator`
    # itself, following that sequence.
    class Job
      include Sidekiq::IterableJob

      # A host reading from a primary/replica split overrides this to
      # return a reader that connects to the replica; the default reads
      # through whatever connection is already active.
      def reader
        Reader::Direct.new
      end

      def each_iteration(row, *args)
        @run.visit(row)
      end

      # Called on every interruption, not only on completion -- this is the
      # "the run is still alive" signal (see `Recorder#flush_segment`), so
      # it must fire whether the run finishes this perform or is interrupted
      # and resumed later.
      #
      # Uninstalling here, rather than leaving it for the next
      # `build_enumerator` to do, keeps the thread-local recorder from
      # surviving into whatever unrelated work this thread picks up next in
      # between Sidekiq perform calls.
      def on_stop
        @recorder.flush_segment(Greenroom.reporter)
        Recorder.uninstall
      end

      # Reads `@recorder`, not `Recorder.current`: Sidekiq calls `on_stop`
      # before `on_complete`, and `on_stop` has already uninstalled the
      # thread-local by the time `on_complete` runs.
      def on_complete
        @recorder.flush_total(Greenroom.reporter)
      end
    end
  end
end
