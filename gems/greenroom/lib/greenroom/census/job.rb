# frozen_string_literal: true

# `sidekiq/iterable_job` alone leaves `Sidekiq::Job` (which supplies `jid`,
# among other things) only partially loaded; the full mixin this job needs
# requires `sidekiq` itself first.
require "sidekiq"
require "sidekiq/iterable_job"

require "greenroom/recorder"
require "greenroom/census/cursor"
require "greenroom/census/middleware"
require "greenroom/census/run"

module Greenroom
  module Census
    # A Sidekiq iterable job that turns a host's target (see `Census::Run`)
    # into a nightly census: a recorder is installed for exactly the
    # duration of one run, so the experiment it drives is on only inside
    # this job (see `ExperimentBehavior#enabled?`).
    #
    # A host subclasses this and defines `target(*args)`, returning an
    # object with `experiment`, `scope`, and `call` (see the README). A
    # target whose `scope` is an ActiveRecord relation needs nothing else;
    # a target whose `scope` is something else overrides `row_enumerator`
    # below instead.
    class Job
      include Sidekiq::IterableJob

      # A host reading from a primary/replica split overrides this to
      # return a reader that connects to the replica; the default reads
      # through whatever connection is already active.
      def reader
        Reader::Direct.new
      end

      # The hook `Sidekiq::Job::Iterable#perform` calls to get this run's
      # row source, on the first call and again on every resume. A
      # subclass cannot supply its row source through `super`: the host's
      # rows are only needed after `Cursor.split` has pulled greenroom's
      # own position out of the combined cursor Sidekiq hands back, and
      # `super` would still be carrying the cursor before that split.
      # `row_enumerator` below is the seam a subclass overrides instead.
      def build_enumerator(*args, cursor:)
        assert_middleware_registered!
        # A second, narrower guard than `Census::Middleware`'s own: this
        # one only protects one census job from a recorder a *previous*
        # census job left installed on this thread. It cannot help an
        # unrelated job, which is why the middleware above is still
        # required (see its own comment for that general case).
        Recorder.uninstall
        position, counts = Cursor.split(cursor)
        @target = target(*args)
        @recorder = Recorder.new(run_id: jid, experiment: @target.experiment)
        @recorder.restore(counts) if counts
        Recorder.install(@recorder)
        @run = Run.new(target: @target, recorder: @recorder, reader: reader)
        Cursor.decorate(row_enumerator(*args, cursor: position), @recorder)
      end

      # The default row source: `active_record_records_enumerator` comes
      # from `Sidekiq::IterableJob` itself, so a target whose `scope` is an
      # ActiveRecord relation needs nothing else. A target whose `scope` is
      # not an ActiveRecord relation (an array, a CSV) overrides this
      # method alone -- `build_enumerator` above stays correct regardless
      # of where the rows actually come from.
      #
      # `cursor:` names the position alone here, in the vocabulary a host
      # already knows from Sidekiq's own helper (its `cursor:` carries the
      # same meaning). The combined `{"position" => ..., "counts" => ...}`
      # cursor `build_enumerator` receives is greenroom's own bookkeeping;
      # a subclass overriding this method never sees it.
      def row_enumerator(*args, cursor:)
        active_record_records_enumerator(@target.scope, cursor: cursor)
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

      private

      # Raised before `build_enumerator` reads a single row (see the
      # comment on `Census::Middleware` for why a missing registration
      # matters): a host that forgot to add the middleware would otherwise
      # only discover the gap the first time a row raises in production,
      # when the leak it causes is already live on some other job.
      def assert_middleware_registered!
        return if Sidekiq.default_configuration.server_middleware.exists?(Middleware)

        raise MiddlewareNotRegisteredError,
          "Greenroom::Census::Middleware is not registered as a Sidekiq server " \
          "middleware. Add it inside Sidekiq.configure_server: " \
          "`config.server_middleware { |chain| chain.add Greenroom::Census::Middleware }`."
      end
    end
  end
end
