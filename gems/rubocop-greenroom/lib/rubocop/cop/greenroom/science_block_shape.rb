# frozen_string_literal: true

module RuboCop
  module Cop
    module Greenroom
      # Requires a `Scientist.run` block to hold `use`, `try`, and `compare`,
      # once each, in that order, and to hold nothing else.
      #
      # The order carries weight beyond taste. The gate that decides whether a
      # change may merge compares the method body before the change against the
      # body inside `use`. A fixed shape lets it find `use` directly, and a
      # free arrangement would put a search in front of that comparison. A
      # reader who wants to write the shape by hand also gets one form to copy
      # rather than several.
      #
      # This cop reports what one file shows, so silence means that this cop
      # cannot tell rather than that a change is accepted.
      class ScienceBlockShape < Base
        MSG = "A Scientist.run block must contain use, try, and compare once, in that order."

        def on_block(node)
          return unless science_block?(node)

          calls = body_expressions(node).map { |expression| science_call(expression, node) }
          add_offense(node.send_node) unless calls == %i[use try compare]
        end

        private

        def science_block?(node)
          send_node = node.send_node
          receiver = send_node.receiver
          send_node.method?(:run) && receiver&.const_type? && receiver.const_name == "Scientist"
        end

        def body_expressions(node)
          body = node.body
          return [] unless body

          body.begin_type? ? body.children : [body]
        end

        def science_call(expression, science_block)
          return unless expression.block_type?

          send_node = expression.send_node
          receiver = send_node.receiver
          argument_name = science_block.arguments.one? && science_block.arguments.first.children.first
          return unless receiver&.lvar_type? && receiver.children.first == argument_name

          send_node.method_name
        end
      end
    end
  end
end
