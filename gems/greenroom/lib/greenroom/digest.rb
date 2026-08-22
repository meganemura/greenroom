# frozen_string_literal: true

require "digest"

module Greenroom
  # Turns an observed value into a short, fixed-length digest for a sample
  # event. Never carries the value itself, only evidence that two values did
  # or did not match.
  module Digest
    module_function

    # Value stability is the host's job, via Scientist's own `clean` block --
    # this module only shortens whatever that block already produced. The
    # default #inspect can embed an object's memory address, so a host that
    # needs a digest to stay stable across runs must write a `clean` block
    # rather than rely on this method to normalize the value.
    #
    # `::Digest::SHA256`, not `SHA256`: this module is itself named `Digest`,
    # so an unqualified `Digest::SHA256` would resolve to
    # `Greenroom::Digest::SHA256` (itself) under Ruby's lexical scoping,
    # rather than the standard library's `::Digest` module.
    def of(value)
      return nil if value.nil?

      ::Digest::SHA256.hexdigest(value.inspect)
    end
  end
end
