# frozen_string_literal: true

module Greenroom
  module Census
    # Bundles the recorder's counts into the cursor Sidekiq's Iteration
    # persists to Redis on every row, so that a resume after an
    # interruption restarts the counts at the same row it restarts
    # iteration at.
    #
    # Sidekiq writes whichever cursor was attached to the row it stopped
    # on, and resumes iteration from that row. If the counts were kept
    # anywhere else (an instance variable, a separate Redis key updated on
    # its own schedule), a resume could restart iteration at row N while
    # the counts still reflected some other row -- double-counting or
    # skipping whatever rows fell in the gap. Attaching the snapshot to the
    # very cursor that names the resume position keeps position and counts
    # describing the same instant, across a plain interruption and across
    # `each_iteration` raising (Sidekiq flushes the last cursor either way).
    module Cursor
      module_function

      # Wraps `enumerator`, which must itself yield `[object, position]`
      # pairs. Built with `Enumerator.new` and read from `enumerator` lazily
      # -- one pair at a time, only as the caller pulls -- rather than
      # eagerly, because eagerly building every pair up front would read
      # `recorder.snapshot` once, at build time, instead of once per row.
      # Every row would then carry the same stale counts, and a resume from
      # any of them would replay rows already processed.
      def decorate(enumerator, recorder)
        Enumerator.new do |yielder|
          enumerator.each do |object, position|
            yielder << [object, {"position" => position, "counts" => recorder.snapshot}]
          end
        end
      end

      # The inverse of the "counts" half of `decorate`: given the cursor
      # Sidekiq handed back on resume (or nil, on a fresh start), returns
      # `[position, counts]` so a caller can feed `position` back into its
      # own enumerator and `counts` into `Recorder#restore`.
      def split(cursor)
        return [nil, nil] if cursor.nil?

        [cursor["position"], cursor["counts"]]
      end
    end
  end
end
