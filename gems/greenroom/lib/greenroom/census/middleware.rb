# frozen_string_literal: true

require "greenroom/recorder"

module Greenroom
  module Census
    # A Sidekiq server middleware that closes the one gap `Census::Job`
    # cannot close on its own: when `each_iteration` raises, Sidekiq
    # re-raises out of `perform` without calling `on_stop`, so the
    # thread-local recorder `build_enumerator` installed is never
    # uninstalled. Sidekiq reuses worker threads across jobs, so without
    # this middleware, the next unrelated job Sidekiq happens to run on that
    # thread would find an experiment already turned on -- the one safety
    # property this gem promises (a candidate runs only inside a census)
    # would be broken by an ordinary job failure.
    #
    # `Census::Job#build_enumerator` also uninstalls at its own start, as a
    # second, narrower guard between one census job and the next -- but that
    # only covers census jobs calling each other; it cannot help an
    # unrelated job. A host must add this middleware to its Sidekiq server
    # middleware chain for the guarantee to hold in general.
    class Middleware
      def call(_job_instance, _job_payload, _queue)
        yield
      ensure
        Greenroom::Recorder.uninstall
      end
    end
  end
end
