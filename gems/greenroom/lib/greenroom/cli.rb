# frozen_string_literal: true

require "optparse"

module Greenroom
  module CLI
    class << self
      def run(arguments, stdout: $stdout, stderr: $stderr)
        command = arguments.first
        return usage(stderr, "A command is required.") unless command
        return usage(stderr, "The judge command is not available.") if command == "judge"
        return usage(stderr, "Unknown command: #{command}.") unless command == "check"

        require_relative "cli/check"
        Check.run(arguments.drop(1), stdout:, stderr:)
      end

      private

      def usage(stderr, message)
        stderr.puts(message)
        stderr.puts("Usage: greenroom check [--json] [commit]")
        2
      end
    end
  end
end
