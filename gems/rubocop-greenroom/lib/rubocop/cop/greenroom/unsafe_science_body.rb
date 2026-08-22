# frozen_string_literal: true

module RuboCop
  module Cop
    module Greenroom
      # Rejects the two constructs that change meaning when a method body moves
      # into a science block.
      #
      # A greenroom change moves an existing body, unchanged, into the `use`
      # block. Most constructs survive that move: a trial of `yield`, of
      # `rescue` and `ensure` written directly in the method, of `__method__`,
      # of local variables, and of a constant read from the same lexical place,
      # each behaved the same before and after the move. Two did not, and this
      # cop names those two. The trial covered one form of each construct, so
      # treat the list as measured rather than complete.
      #
      # `return` leaves the enclosing method from inside the block, so the
      # comparison and the publication never run, and the experiment reports
      # nothing while appearing to work.
      #
      # `binding` reports the block's local variables rather than the method's,
      # so the same expression describes a different scope after the move.
      #
      # This cop reports what one file shows. The gate that decides whether a
      # change may merge reads the version before the change as well, so
      # silence here means that this cop cannot tell, rather than that a change
      # is accepted.
      class UnsafeScienceBody < Base
        RETURN_MESSAGE = "A return in a science body bypasses comparison and publication."
        BINDING_MESSAGE = "A binding in a science body observes the block scope."

        def on_return(node)
          add_offense(node, message: RETURN_MESSAGE) if unsafe_return?(node)
        end

        def on_send(node)
          return unless node.receiver.nil? && node.method?(:binding)
          return unless science_body_ancestor(node)

          add_offense(node, message: BINDING_MESSAGE)
        end

        private

        # Walks outward and answers for the nearest scope that a `return`
        # leaves. A `return` inside a nested `def` or a lambda returns from
        # that def or that lambda, and it goes to the same place before and
        # after the move, so this cop stays quiet. A `proc` and an ordinary
        # block both return from the enclosing method, so they carry the same
        # hazard as a bare `return` and this cop reports them.
        def unsafe_return?(node)
          node.each_ancestor do |ancestor|
            return false if ancestor.def_type? || ancestor.defs_type?
            return false if ancestor.block_type? && ancestor.lambda?
            return true if science_body_block?(ancestor)
          end

          false
        end

        def science_body_ancestor(node)
          node.each_ancestor.find { |ancestor| science_body_block?(ancestor) }
        end

        # A block counts as a science body when it is `use` or `try` called on
        # the parameter that `Scientist.run` yielded. Matching the parameter
        # rather than the method name alone keeps the cop quiet about an
        # unrelated `use` or `try` that happens to sit inside another block.
        def science_body_block?(node)
          return false unless node.block_type? && %i[use try].include?(node.send_node.method_name)

          science_block = node.each_ancestor.find(&:block_type?)
          return false unless science_block

          science_send = science_block.send_node
          receiver = science_send.receiver
          return false unless science_send.method?(:run) && receiver&.const_name == "Scientist"

          body_receiver = node.send_node.receiver
          argument_name = science_block.arguments.one? && science_block.arguments.first.children.first
          body_receiver&.lvar_type? && body_receiver.children.first == argument_name
        end
      end
    end
  end
end
