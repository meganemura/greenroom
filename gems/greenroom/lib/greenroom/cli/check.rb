# frozen_string_literal: true

require "json"
require "open3"
require "optparse"

module Greenroom
  module CLI
    module Check
      Result = Data.define(:accepted, :message, :experiment, :candidate)

      class << self
        def run(arguments, stdout: $stdout, stderr: $stderr)
          json = false
          parser = OptionParser.new do |options|
            options.banner = "Usage: greenroom check [--json] [commit]"
            options.on("--json") { json = true }
          end
          parser.parse!(arguments)
          return usage(stderr, parser) if arguments.length > 1

          require "rubocop-ast"
          result = Repository.new(Dir.pwd).check(arguments.first || "HEAD")
          print_result(stdout, result, json)
          result.accepted ? 0 : 1
        rescue OptionParser::ParseError => error
          stderr.puts(error.message)
          stderr.puts(parser)
          2
        end

        private

        def usage(stderr, parser)
          stderr.puts("One commit is allowed.")
          stderr.puts(parser)
          2
        end

        def print_result(stdout, result, json)
          if json
            stdout.puts(JSON.generate({
              accepted: result.accepted,
              message: result.message,
              experiment: result.experiment,
              candidate: result.candidate
            }))
          else
            stdout.puts(result.message)
          end
        end
      end

      # This check gates an automatic merge. The RuboCop check sees one file
      # version, so it cannot compare the new method body with the old body.
      class Repository
        def initialize(directory)
          @directory = directory
        end

        def check(commit)
          resolved = git("rev-parse", "--verify", "#{commit}^{commit}").strip
          parents = git("rev-list", "--parents", "-n", "1", resolved).split.drop(1)
          # A merge has more than one source state. A comparison with its first
          # parent would give a different meaning to the acceptance result.
          return reject("The commit is a merge commit.") if parents.length > 1
          return reject("The commit has no parent.") if parents.empty?

          changes = git("diff-tree", "--no-commit-id", "--name-status", "-r", "-M20%", parents.first, resolved).lines
          # A rejected shape goes to human review. Thus, an uncertain result
          # must reject instead of accepting a change for an automatic merge.
          return reject("The commit must modify one Ruby file.") unless changes.one?

          fields = changes.first.chomp.split("\t")
          # Git can report a rename as R or as an addition and a deletion.
          # Requiring one M entry rejects both forms and their identity change.
          return reject("The changed file must have status M.") unless fields.length == 2 && fields.first == "M"

          path = fields.last
          return reject("The changed file must have the .rb extension.") unless path.end_with?(".rb")

          # Complete blobs support a syntax tree comparison across both file
          # versions. Parsing unified diff lines would mix syntax with context.
          before = git("show", "#{parents.first}:#{path}")
          after = git("show", "#{resolved}:#{path}")
          Analyzer.new(before, after).check
        rescue GitError, Analyzer::SourceError => error
          reject(error.message)
        end

        private

        GitError = Class.new(StandardError)

        def git(*arguments)
          stdout, _stderr, status = Open3.capture3("git", *arguments, chdir: @directory)
          raise GitError, "Git could not read the commit." unless status.success?

          stdout
        end

        def reject(message)
          Result.new(false, message, nil, nil)
        end
      end

      class Analyzer
        SourceError = Class.new(StandardError)
        Scope = Data.define(:name, :node, :methods, :statements)
        Experiment = Data.define(:name, :method, :use_block, :candidate)

        def initialize(before, after)
          # Syntax trees omit source locations. Therefore, comment and white
          # space positions do not affect the acceptance result.
          @before = parse(before)
          @after = parse(after)
        end

        def check
          return reject("Unsupported Ruby method or class syntax is present.") if unsupported?(@before) || unsupported?(@after)

          before_scopes = scopes(@before)
          after_scopes = scopes(@after)
          return reject("The class and module structure changed.") unless before_scopes.keys == after_scopes.keys
          return reject("The class or module header changed.") unless before_scopes.all? { |name, scope| same_header?(scope, after_scopes.fetch(name)) }
          return reject("A top-level statement changed.") unless top_level(@before) == top_level(@after)

          changed = []
          added = []
          before_scopes.each do |name, before_scope|
            after_scope = after_scopes.fetch(name)
            removed_names = before_scope.methods.keys - after_scope.methods.keys
            return reject("An existing method was removed.") unless removed_names.empty?

            common_names = before_scope.methods.keys & after_scope.methods.keys
            common_names.each do |method_name|
              changed << [name, before_scope.methods.fetch(method_name), after_scope.methods.fetch(method_name)] unless same_ast?(before_scope.methods.fetch(method_name), after_scope.methods.fetch(method_name))
            end
            (after_scope.methods.keys - before_scope.methods.keys).each do |method_name|
              added << [name, after_scope.methods.fetch(method_name)]
            end
          end

          return reject("Exactly one existing method must change.") unless changed.one?
          return reject("Exactly one candidate method must be added.") unless added.one?

          scope_name, before_method, after_method = changed.first
          added_scope_name, candidate = added.first
          return reject("The candidate method must be in the changed class.") unless scope_name == added_scope_name
          return reject("The candidate method must be private.") unless private_method?(after_scopes.fetch(scope_name), candidate)
          return reject("An existing method visibility changed.") unless same_visibilities?(before_scopes.fetch(scope_name), after_scopes.fetch(scope_name))
          return reject("Another class body statement changed.") unless unchanged_statements?(before_scopes.fetch(scope_name), after_scopes.fetch(scope_name), candidate)
          return reject("The changed method signature must stay the same.") unless same_ast?(before_method.children[1], after_method.children[1])
          other_scope_changed = before_scopes.any? do |name, before_scope|
            next false if name == scope_name

            after_scope = after_scopes.fetch(name)
            !unchanged_statements?(before_scope, after_scope)
          end
          return reject("Another class or module changed.") if other_scope_changed

          science = science_blocks(after_method)
          unless science
            shape_error = science_shape_error(after_method)
            return reject(shape_error || "The changed method body must contain one Scientist.run call.")
          end

          use_block, try_block, _compare_block, experiment, science_statement = science
          return reject("The use block must match the old method body.") unless matching_span?(before_method, after_method, science_statement, use_block)
          # Tests found behavior changes when statements move into a block.
          # A return in the moved part bypasses compare and publish.
          # A binding sees the block's local variables. Tests found the same
          # behavior for yield, rescue, ensure, __method__, local variables,
          # and constant references, so those forms remain valid.
          return reject("A return in a use or try block is unsafe.") if unsafe_return?(use_block) || unsafe_return?(try_block)
          return reject("A binding in a use or try block is unsafe.") if binding_call?(use_block) || binding_call?(try_block)

          candidate_name = candidate.children[0]
          Result.new(true, "Accepted experiment #{experiment} with candidate #{candidate_name}.", experiment, candidate_name.to_s)
        end

        # The judge uses the same structural relation that the merge gate
        # verifies. A second parser could accept a shape that the gate rejects.
        def experiments
          scopes(@after).values.flat_map do |scope|
            scope.methods.values.filter_map do |method|
              science = science_blocks(method)
              next unless science

              use_block, try_block, _compare_block, name = science
              try_body = block_body(try_block)
              next unless try_body&.send_type? && try_body.receiver.nil?

              candidate = scope.methods[try_body.method_name]
              Experiment.new(name, method, use_block, candidate) if candidate
            end
          end
        end

        private

        def parse(source)
          processed = RuboCop::AST::ProcessedSource.new(source, 3.2)
          raise SourceError, "The Ruby source has a syntax error." unless processed.valid_syntax?

          processed.ast
        end

        def scopes(root)
          found = {}
          walk_scopes(root, [], found)
          found
        end

        def walk_scopes(node, namespace, found)
          return unless node.is_a?(RuboCop::AST::Node)

          if node.class_type? || node.module_type?
            name_node = node.children[0]
            raise SourceError, "Anonymous classes are not supported." unless name_node&.const_type?

            name = constant_name(name_node, namespace)
            raise SourceError, "A class or module is reopened in this file." if found.key?(name)

            body = node.class_type? ? node.children[2] : node.children[1]
            statements = body&.begin_type? ? body.children : [body].compact
            definitions = statements.select(&:def_type?)
            methods = definitions.to_h { |method| [method.children[0], method] }
            raise SourceError, "Duplicate method definitions are not supported." unless definitions.length == methods.length

            found[name] = Scope.new(name, node, methods, statements)
            statements.each { |statement| walk_scopes(statement, name.split("::"), found) unless statement.def_type? }
          else
            node.children.each { |child| walk_scopes(child, namespace, found) }
          end
        end

        def constant_name(node, namespace)
          parent, name = node.children
          return (namespace + [name.to_s]).join("::") unless parent

          [constant_name(parent, []), name].join("::")
        end

        def same_ast?(left, right)
          ast_value(left) == ast_value(right)
        end

        def ast_value(value)
          return value unless value.is_a?(RuboCop::AST::Node)

          [value.type, *value.children.map { |child| ast_value(child) }]
        end

        def method_body(method)
          method.children[2]
        end

        def block_body(block)
          block.children[2]
        end

        def science_blocks(method)
          science_statements = method_statements(method).filter_map do |statement|
            science_block = if statement.block_type?
              statement
            elsif statement.lvasgn_type? && statement.children[1]&.block_type?
              statement.children[1]
            end
            [statement, science_block] if scientist_run_block?(science_block)
          end
          return unless science_statements.one?

          science_statement, science_block = science_statements.first

          send_node, arguments, science_body = science_block.children
          return unless send_node.send_type? && send_node.method?(:run)
          return unless send_node.receiver&.const_type? && send_node.receiver.const_name == "Scientist"
          return unless send_node.arguments.one? && send_node.arguments.first.str_type?
          return unless arguments.one?

          experiment_variable = arguments.children.first.children.first
          expressions = science_body&.begin_type? ? science_body.children : [science_body].compact
          return unless expressions.length == 3

          methods = %i[use try compare]
          return unless expressions.each_with_index.all? do |expression, index|
            expression.block_type? && expression.send_node.method?(methods[index]) &&
              expression.send_node.receiver&.lvar_type? && expression.send_node.receiver.children.first == experiment_variable
          end

          [*expressions, send_node.arguments.first.value, science_statement]
        end

        def science_shape_error(method)
          statement = method_statements(method).find do |item|
            each_node(item).any? { |node| scientist_run_block?(node) }
          end
          return unless statement

          direct_block = statement.lvasgn_type? ? statement.children[1] : statement
          return if scientist_run_block?(direct_block)

          if statement.masgn_type?
            "The Scientist.run statement must be a bare call or a local variable assignment."
          else
            "The Scientist.run call must be a direct method body statement."
          end
        end

        def scientist_run_block?(node)
          return false unless node&.block_type?

          send_node = node.send_node
          send_node.method?(:run) && send_node.receiver&.const_type? && send_node.receiver.const_name == "Scientist"
        end

        def matching_span?(before_method, after_method, science_statement, use_block)
          before = method_statements(before_method)
          after = method_statements(after_method)
          science_index = after.index(science_statement)
          suffix_length = after.length - science_index - 1
          middle_end = before.length - suffix_length
          return false unless middle_end > science_index

          # A statement outside the block keeps its position and behavior.
          # Thus, the science block can wrap one body span.
          prefix_matches = statement_values(before.take(science_index)) == statement_values(after.take(science_index))
          suffix_matches = statement_values(before.drop(middle_end)) == statement_values(after.drop(science_index + 1))
          middle = before[science_index...middle_end]
          use = node_statements(block_body(use_block))
          use_matches = if science_statement.lvasgn_type?
            assignment = middle.last
            assignment&.lvasgn_type? && assignment.children.first == science_statement.children.first &&
              statement_values([*middle[0...-1], assignment.children[1]]) == statement_values(use)
          else
            statement_values(middle) == statement_values(use)
          end
          prefix_matches && suffix_matches && use_matches
        end

        def method_statements(method)
          node_statements(method_body(method))
        end

        def node_statements(node)
          node&.begin_type? ? node.children : [node].compact
        end

        def private_method?(scope, method)
          visibility_at(scope, method) == :private
        end

        def visibility_at(scope, method)
          visibility = :public
          scope.statements.each do |statement|
            visibility = statement.method_name if visibility_call?(statement)
            return visibility if statement.equal?(method)
          end
          nil
        end

        def visibility_call?(node)
          node.send_type? && node.receiver.nil? && %i[public protected private].include?(node.method_name) && node.arguments.empty?
        end

        def unchanged_statements?(before_scope, after_scope, candidate = nil)
          before = before_scope.statements.reject(&:def_type?)
          after = after_scope.statements.reject(&:def_type?).dup
          if candidate
            candidate_index = after_scope.statements.index(candidate)
            marker = after_scope.statements[0...candidate_index].reverse.find { |statement| visibility_call?(statement) }
            before_private_count = before.count { |statement| statement.send_type? && statement.method?(:private) }
            after_private_count = after.count { |statement| statement.send_type? && statement.method?(:private) }
            after.delete_at(after.index(marker)) if marker&.method?(:private) && after_private_count == before_private_count + 1
          end
          statement_values(before) == statement_values(after)
        end

        def same_visibilities?(before_scope, after_scope)
          before_scope.methods.all? do |name, method|
            visibility_at(before_scope, method) == visibility_at(after_scope, after_scope.methods.fetch(name))
          end
        end

        def same_header?(before_scope, after_scope)
          before_node = before_scope.node
          after_node = after_scope.node
          count = before_node.class_type? ? 2 : 1
          same_ast?(sequence(before_node.children.take(count)), sequence(after_node.children.take(count)))
        end

        def top_level(root)
          statements = root&.begin_type? ? root.children : [root].compact
          statement_values(statements)
        end

        def statement_values(statements)
          statements.map do |statement|
            if statement.class_type? || statement.module_type?
              count = statement.class_type? ? 2 : 1
              [:scope, statement.type, *statement.children.take(count).map { |child| ast_value(child) }]
            else
              ast_value(statement)
            end
          end
        end

        def unsupported?(root)
          each_node(root).any? do |node|
            node.defs_type? || node.sclass_type? ||
              (node.send_type? && node.method?(:define_method)) ||
              (node.send_type? && node.method?(:new) && node.receiver&.const_type? && node.receiver.const_name == "Class")
          end
        end

        def sequence(nodes)
          RuboCop::AST::Node.new(:begin, nodes)
        end

        def unsafe_return?(block)
          unsafe_return_in?(block_body(block), [])
        end

        def unsafe_return_in?(node, scopes)
          return false unless node.is_a?(RuboCop::AST::Node)
          return true if node.return_type? && scopes.none? { |scope| scope == :safe }

          # A nested method or lambda owns its return. A proc or a plain block
          # keeps the science block as the nearest return scope.
          child_scopes = scopes
          child_scopes = scopes + [:safe] if node.def_type? || node.defs_type? || (node.block_type? && node.lambda?)
          node.children.any? { |child| unsafe_return_in?(child, child_scopes) }
        end

        def binding_call?(block)
          each_node(block_body(block)).any? { |node| node.send_type? && node.receiver.nil? && node.method?(:binding) }
        end

        def each_node(node, values = [])
          return values unless node.is_a?(RuboCop::AST::Node)

          values << node
          node.children.each { |child| each_node(child, values) }
          values
        end

        def reject(message)
          Result.new(false, message, nil, nil)
        end
      end
    end
  end
end
