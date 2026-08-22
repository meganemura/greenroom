# frozen_string_literal: true

require "date"
require "fileutils"
require "json"
require "open3"
require "optparse"
require "tmpdir"
require "time"
require "yaml"
require_relative "check"

module Greenroom
  module CLI
    module Judge
      DEFAULTS = {
        "minimum_comparisons" => 1000,
        "consecutive_clean_nights" => 2,
        "expiry_days" => 30,
        "minimum_comparison_ratio" => 0.8
      }.freeze
      Verdict = Data.define(:experiment, :verdict, :reason, :patch, :patch_error)

      class << self
        def run(arguments, stdout: $stdout, stderr: $stderr)
          options = {repo: ".", json: false}
          parser = option_parser(options)
          parser.parse!(arguments)
          return usage(stderr, parser, "The --events option is required.") unless options[:events]
          return usage(stderr, parser, "The --config option is required.") unless options[:config]
          return usage(stderr, parser, "Unexpected arguments are present.") unless arguments.empty?

          # The host application CI owns the service credentials and pull
          # request delivery. JSON input keeps these service boundaries outside
          # the gem.
          events = JSON.parse(File.read(options[:events]))
          config = DEFAULTS.merge(YAML.safe_load_file(options[:config]) || {})
          require "rubocop-ast"
          verdicts, errors = Evaluation.new(events, config, options[:repo]).call
          print_results(stdout, verdicts, errors, options[:json])
          # The exit status reports when a person must act. A successful promotion
          # stays green because the host CI uses the JSON result to open its
          # pull request.
          (verdicts.any? { |item| %w[nogo attention expired].include?(item.verdict) }) ? 1 : 0
        rescue OptionParser::ParseError, JSON::ParserError, Errno::ENOENT, Psych::Exception => error
          stderr.puts(error.message)
          2
        end

        private

        def option_parser(options)
          OptionParser.new do |parser|
            parser.banner = "Usage: greenroom judge --events PATH --config PATH [--repo PATH] [--json]"
            parser.on("--events PATH") { |value| options[:events] = value }
            parser.on("--config PATH") { |value| options[:config] = value }
            parser.on("--repo PATH") { |value| options[:repo] = value }
            parser.on("--json") { options[:json] = true }
          end
        end

        def usage(stderr, parser, message)
          stderr.puts(message)
          stderr.puts(parser)
          2
        end

        def print_results(stdout, verdicts, errors, json)
          if json
            stdout.puts(JSON.generate({verdicts: verdicts.map(&:to_h), errors:}))
            return
          end

          verdicts.each do |item|
            line = "#{item.experiment}: #{item.verdict} (#{item.reason})"
            if item.patch_error
              detail = item.patch_error.sub(/\A[A-Z]/) { |character| character.downcase }.delete_suffix(".")
              line = "#{line} -- no patch: #{detail}"
            end
            stdout.puts(line)
            stdout.write(item.patch) if item.patch
          end
          errors.each { |error| stdout.puts("error: #{error}") }
        end
      end

      class Evaluation
        def initialize(events, config, repository)
          @events = events
          @config = config
          @repository = File.expand_path(repository)
        end

        def call
          valid, errors = readable_events
          verdicts = valid.group_by { |event| event.fetch("experiment") }.map do |name, entries|
            evaluate(name, deduplicate(entries))
          end
          [verdicts, errors]
        end

        private

        def readable_events
          valid = []
          errors = []
          @events.each_with_index do |event, index|
            if event["timestamp"]
              valid << event
            else
              errors << "Event #{index + 1} has no timestamp."
            end
          end
          [valid, errors]
        end

        def deduplicate(events)
          # A retry can report the same run again with corrected data. Assignment
          # keeps the later report as the run's final value.
          events.each_with_object({}) { |event, runs| runs[event.fetch("run_id")] = event }.values
            .sort_by { |event| Time.iso8601(event.fetch("timestamp")) }
        end

        def evaluate(name, runs)
          latest = runs.last
          previous = runs[-2]
          verdict, reason = decision(runs, latest, previous)
          patch = %w[go nogo expired].include?(verdict) ? Patch.new(@repository, name, verdict).call : nil
          patch_error = nil
          if patch.is_a?(Array)
            # Event data determines the verdict reason, but repository state
            # determines the patch result. One result must not replace the other.
            patch_error = patch.last
            patch = nil
          end
          Verdict.new(name, verdict, reason, patch, patch_error)
        end

        def decision(runs, latest, previous)
          # Candidate failures, row failures, and a reduced sample question the
          # census itself. A person must validate the census before any
          # patch.
          attention = attention_reason(latest, previous)
          return ["attention", attention] if attention
          return ["nogo", "#{latest.fetch("mismatches")} mismatches"] if latest.fetch("mismatches").positive?
          if expired?(runs, latest)
            return ["expired", "#{latest.fetch("comparisons")} comparisons after #{@config.fetch("expiry_days")} days"]
          end

          # Scheduled runs do not replace a missed night. Counting reported runs
          # prevents a deployment pause from becoming a failed observation.
          clean = runs.reverse.take_while { |run| clean?(run) }.length
          needed = @config.fetch("consecutive_clean_nights")
          return ["go", "#{needed} clean nights, #{latest.fetch("comparisons")} comparisons"] if clean >= needed

          # Most nightly runs cannot support a final decision. Waiting avoids an
          # early promotion and avoids repeated alerts for normal evidence
          # collection.
          ["waiting", "#{clean} of #{needed} clean nights, #{latest.fetch("comparisons")} comparisons"]
        end

        def attention_reason(latest, previous)
          # Control errors describe the established production path. Ignored
          # comparisons remain operational data, but version 1 does not use them
          # for decisions. If either metric caused attention, normal nightly runs
          # would alert a person. Frequent alerts would make each alert less useful.
          return "#{latest.fetch("candidate_errors")} candidate errors" if latest.fetch("candidate_errors").positive?
          return "#{latest.fetch("row_errors")} row errors" if latest.fetch("row_errors").positive?
          # A smaller denominator can make zero mismatches look reliable after
          # the census examines too little data.
          # The comparison needs a prior positive value because a ratio against
          # a missing run or zero is undefined.
          return unless previous&.fetch("comparisons")&.positive?
          return unless latest.fetch("comparisons") < previous.fetch("comparisons") * @config.fetch("minimum_comparison_ratio")

          "comparisons fell from #{previous.fetch("comparisons")} to #{latest.fetch("comparisons")}"
        end

        def expired?(runs, latest)
          # Expiry requires a reported run below the threshold. A missing event
          # means that the census did not run, not that it examined zero rows.
          return false unless latest.fetch("comparisons") < @config.fetch("minimum_comparisons")

          first = Time.iso8601(runs.first.fetch("timestamp"))
          last = Time.iso8601(latest.fetch("timestamp"))
          last - first >= @config.fetch("expiry_days") * 86_400
        end

        def clean?(run)
          run.fetch("mismatches").zero? && run.fetch("comparisons") >= @config.fetch("minimum_comparisons")
        end
      end

      class Patch
        def initialize(repository, experiment, verdict)
          @repository = repository
          @experiment = experiment
          @verdict = verdict
        end

        def call
          matches = find_matches
          # Multiple locations make the patch target ambiguous. The judge stops
          # instead of changing a location that it cannot identify safely.
          return [nil, "The experiment has #{matches.length} locations."] unless matches.one?

          path, source, match = matches.first
          changed = (@verdict == "go") ? promote(source, match) : revert(source, match)
          build(path, source, changed)
        end

        private

        def find_matches
          Dir.glob(File.join(@repository, "**", "*.rb")).filter_map do |path|
            source = File.read(path)
            next unless source.include?(@experiment)

            # The merge gate defines the accepted experiment structure. Reusing
            # its analyzer prevents the judge from patching a shape that the
            # gate rejects.
            analyzer = Check::Analyzer.new(source, source)
            analyzer.experiments.filter { |item| item.name == @experiment }.map { |item| [path, source, item] }
          rescue Check::Analyzer::SourceError
            []
          end.flatten(1)
        end

        def promote(source, match)
          string = match.method.each_descendant(:str).find { |node| node.value == @experiment }
          offset = string.source_range.end_pos
          source.dup.insert(offset, ', run: "candidate"')
        end

        def revert(source, match)
          body = match.method.children[2]
          use_body = match.use_block.children[2]
          changed = source.dup
          candidate_range = full_line_range(changed, match.candidate.source_range)
          # Revert reviews compare the result byte for byte with the source from
          # before the wrap. The separator before the candidate belongs to it.
          preceding_line = changed.rindex("\n", candidate_range.begin - 2)&.+(1) || 0
          candidate_range = preceding_line..candidate_range.end if changed[preceding_line...candidate_range.begin].strip.empty?
          changed.slice!(candidate_range)
          replace(changed, body.source_range, use_body.source)
        end

        def replace(source, range, replacement)
          source.dup.tap { |value| value[range.begin_pos...range.end_pos] = replacement }
        end

        def full_line_range(source, range)
          start = source.rindex("\n", range.begin_pos - 1)&.+(1) || 0
          finish = source.index("\n", range.end_pos) || source.length - 1
          start..finish
        end

        def build(path, before, after)
          # The host application owns its working tree and pull requests. A
          # unified diff lets that host inspect and apply the change itself.
          relative = path.delete_prefix("#{@repository}/")
          Dir.mktmpdir("greenroom-judge-patch") do |directory|
            %w[a b].each { |side| FileUtils.mkdir_p(File.join(directory, side, File.dirname(relative))) }
            File.write(File.join(directory, "a", relative), before)
            File.write(File.join(directory, "b", relative), after)
            stdout, _stderr, _status = Open3.capture3("git", "diff", "--no-index", "--", "a/#{relative}", "b/#{relative}", chdir: directory)
            stdout.gsub("a/a/#{relative}", "a/#{relative}").gsub("b/b/#{relative}", "b/#{relative}")
          end
        end
      end
    end
  end
end
