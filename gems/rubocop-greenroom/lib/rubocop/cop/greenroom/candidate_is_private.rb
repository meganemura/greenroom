# frozen_string_literal: true

module RuboCop
  module Cop
    module Greenroom
      # Requires the candidate method that `try` calls to be private.
      #
      # A candidate is scaffolding. Once the experiment wins, a later change
      # folds the candidate into the method body and deletes the scaffolding. A
      # public candidate invites a caller from outside the class, and that
      # deletion then breaks the caller. A private one keeps the deletion
      # inside the class that owns it.
      #
      # The cop answers only when this file shows the answer: the `try` body
      # must be one call to the object itself, and the definition must sit in
      # the same class. A definition in another file leaves this cop quiet,
      # because the gate that reads the whole change decides that case.
      class CandidateIsPrivate < Base
        include VisibilityHelp

        MSG = "A candidate method must be private."

        def on_block(node)
          return unless science_try_block?(node)

          candidate_call = node.body
          return unless candidate_call&.send_type?
          return unless candidate_call.receiver.nil? || candidate_call.receiver.self_type?

          class_node = node.each_ancestor.find(&:class_type?)
          return unless class_node

          definition = candidate_definition(class_node, candidate_call.method_name)
          return unless definition
          return if node_visibility(definition) == :private

          add_offense(node)
        end

        private

        def science_try_block?(node)
          return false unless node.send_node.method?(:try)

          science_block = node.each_ancestor.find(&:block_type?)
          return false unless science_block

          science_send = science_block.send_node
          receiver = science_send.receiver
          return false unless science_send.method?(:run) && receiver&.const_name == "Scientist"

          try_receiver = node.send_node.receiver
          argument_name = science_block.arguments.one? && science_block.arguments.first.children.first
          try_receiver&.lvar_type? && try_receiver.children.first == argument_name
        end

        def candidate_definition(class_node, method_name)
          class_node.each_descendant(:def).find do |definition|
            definition.method_name == method_name &&
              definition.each_ancestor.find(&:class_type?) == class_node
          end
        end
      end
    end
  end
end
