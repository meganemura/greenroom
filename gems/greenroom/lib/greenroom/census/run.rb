# frozen_string_literal: true

module Greenroom
  module Census
    # Where a row is actually read from. `Direct` just calls the block; a
    # replica-reading implementation (`ActiveRecord::Base.connected_to(role:
    # :reading, prevent_writes: true)`) is a separate concern from the
    # census core and is not implemented here -- this one-method interface
    # (`#call { }`) is fixed now so a host can supply its own without
    # touching `Run`.
    module Reader
      class Direct
        def call
          yield
        end
      end
    end

    # Does the work of one row: freeze it, count it, tell the recorder which
    # row is being looked at, then call the host's target through the
    # reader. Kept as a single, small method so a census job's
    # `each_iteration` (see `Census::Job`) is just `@run.visit(row)`.
    class Run
      def initialize(target:, recorder:, reader:)
        @target = target
        @recorder = recorder
        @reader = reader
      end

      # The control and candidate blocks run on the same row object, and
      # Scientist shuffles their execution order; without freezing, a
      # candidate's write would look like a mismatch caused by the control
      # (or vice versa) rather than what it is, a bug in that one row's
      # candidate.
      #
      # A raising row is caught here rather than left to escape: one bad row
      # must not stop the rest of the census, and `record_row_error` keeps
      # the count of rows that never reached a comparison visible instead of
      # silently inflating `rows_scanned` beyond what was actually examined.
      # `StandardError`, not `Exception`, so a signal like `SystemExit`
      # still propagates; `Census::Middleware` is this gem's backstop for a
      # row that escapes some other way.
      def visit(row)
        row.freeze
        @recorder.count_row
        @recorder.subject = subject_for(row)
        @reader.call { @target.call(row) }
      rescue => e
        @recorder.record_row_error(e)
      end

      private

      def subject_for(row)
        row.id if row.respond_to?(:id)
      end
    end
  end
end
