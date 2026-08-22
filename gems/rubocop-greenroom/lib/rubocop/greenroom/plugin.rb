# frozen_string_literal: true

require "lint_roller"
require "pathname"

module RuboCop
  module Greenroom
    class Plugin < LintRoller::Plugin
      def about
        LintRoller::About.new(
          name: "rubocop-greenroom",
          version: VERSION,
          homepage: "https://github.com/meganemura/greenroom",
          description: "RuboCop rules for Greenroom science blocks"
        )
      end

      def supported?(context)
        context.engine == :rubocop
      end

      def rules(_context)
        LintRoller::Rules.new(
          type: :path,
          config_format: :rubocop,
          value: Pathname.new(__dir__).join("../../../config/default.yml")
        )
      end
    end
  end
end
