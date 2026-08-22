# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "tmpdir"
require "yaml"
require_relative "../../test_helper"

class GreenroomCLIJudgeTest < Minitest::Test
  ORIGINAL = <<~RUBY
    class Pricing
      def compute(order)
        order.subtotal * rate(order)
      end

      private

      def rate(order)
        order.premium? ? 1.2 : 1.0
      end
    end
  RUBY

  WRAPPED = <<~RUBY
    class Pricing
      def compute(order)
        Scientist.run "price-v2" do |experiment|
          experiment.use { order.subtotal * rate(order) }
          experiment.try { compute_v2(order) }
          experiment.compare { |control, candidate| control == candidate }
        end
      end

      private

      def compute_v2(order)
        order.subtotal * new_rate(order)
      end

      def rate(order)
        order.premium? ? 1.2 : 1.0
      end
    end
  RUBY

  def test_promotes_after_two_clean_runs_and_outputs_an_applicable_patch
    in_repository do |repository|
      write(repository, "pricing.rb", WRAPPED)
      events = [event("first", "2026-08-20T02:00:00Z"), event("second", "2026-08-22T02:00:00Z")]

      stdout, stderr, status = run_judge(repository, events)

      assert_predicate status, :success?, stderr
      assert_match(/^price-v2: go \(2 clean nights, 1200 comparisons\)$/i, stdout.lines.first.chomp)
      patch = stdout.lines.drop(1).join
      apply(repository, patch)
      assert_includes File.read(File.join(repository, "pricing.rb")), 'Scientist.run "price-v2", run: "candidate" do'
      assert_empty stderr
    end
  end

  def test_reverts_a_mismatch_to_the_use_body
    in_repository do |repository|
      write(repository, "pricing.rb", WRAPPED)
      events = [event("first", "2026-08-20T02:00:00Z", "mismatches" => 1)]

      stdout, stderr, status = run_judge(repository, events)

      assert_equal 1, status.exitstatus
      assert_match(/^price-v2: nogo /, stdout, stderr)
      apply(repository, stdout.lines.drop(1).join)
      source = File.read(File.join(repository, "pricing.rb"))
      assert_includes source, "    order.subtotal * rate(order)\n"
      refute_includes source, "Scientist.run"
      refute_includes source, "compute_v2"
    end
  end

  def test_revert_restores_the_exact_source_from_before_the_wrap
    in_repository do |repository|
      write(repository, "pricing.rb", WRAPPED)
      events = [event("first", "2026-08-20T02:00:00Z", "mismatches" => 1)]

      stdout, _stderr, _status = run_judge(repository, events)

      apply(repository, stdout.lines.drop(1).join)
      assert_equal ORIGINAL.b, File.binread(File.join(repository, "pricing.rb"))
    end
  end

  def test_waits_for_the_second_clean_run
    in_repository do |repository|
      write(repository, "pricing.rb", WRAPPED)

      stdout, _stderr, status = run_judge(repository, [event("first", "2026-08-20T02:00:00Z")])

      assert_predicate status, :success?
      assert_equal "price-v2: waiting (1 of 2 clean nights, 1200 comparisons)\n", stdout
    end
  end

  def test_applies_attention_before_nogo
    result = run_json([event("first", "2026-08-20T02:00:00Z", "mismatches" => 1, "candidate_errors" => 1)])

    assert_equal "attention", result.fetch("verdicts").first.fetch("verdict")
    assert_nil result.fetch("verdicts").first.fetch("patch")
  end

  def test_applies_nogo_before_expired
    config = {"expiry_days" => 1}
    events = [event("first", "2026-08-20T02:00:00Z", "comparisons" => 10, "mismatches" => 1),
      event("second", "2026-08-22T02:00:00Z", "comparisons" => 10, "mismatches" => 1)]

    result = run_json(events, config:)

    assert_equal "nogo", result.fetch("verdicts").first.fetch("verdict")
  end

  def test_reports_attention_for_candidate_row_and_denominator_errors
    {
      "candidate_errors" => 1,
      "row_errors" => 1
    }.each do |field, value|
      result = run_json([event("first", "2026-08-20T02:00:00Z", field => value)])
      assert_equal "attention", result.fetch("verdicts").first.fetch("verdict")
    end

    events = [event("first", "2026-08-20T02:00:00Z", "comparisons" => 2000),
      event("second", "2026-08-21T02:00:00Z", "comparisons" => 1599)]
    assert_equal "attention", run_json(events).fetch("verdicts").first.fetch("verdict")
  end

  def test_does_not_use_control_errors_ignored_or_an_undefined_ratio_for_attention
    first = event("first", "2026-08-20T02:00:00Z", "comparisons" => 0, "control_errors" => 4, "ignored" => 8)
    second = event("second", "2026-08-21T02:00:00Z", "comparisons" => 1200)

    assert_equal "waiting", run_json([first]).fetch("verdicts").first.fetch("verdict")
    assert_equal "waiting", run_json([first, second]).fetch("verdicts").first.fetch("verdict")
  end

  def test_expires_low_comparison_runs_after_the_configured_period
    events = [event("first", "2026-08-20T02:00:00Z", "comparisons" => 10),
      event("second", "2026-08-22T02:00:00Z", "comparisons" => 10)]

    result = run_json(events, config: {"expiry_days" => 1})

    assert_equal "expired", result.fetch("verdicts").first.fetch("verdict")
    assert_kind_of String, result.fetch("verdicts").first.fetch("patch")
  end

  def test_keeps_runs_consecutive_across_a_missing_calendar_night
    events = [event("first", "2026-08-20T02:00:00Z"), event("second", "2026-08-22T02:00:00Z")]

    assert_equal "go", run_json(events).fetch("verdicts").first.fetch("verdict")
  end

  def test_keeps_the_later_duplicate_run
    events = [event("same", "2026-08-20T01:00:00Z", "mismatches" => 1),
      event("same", "2026-08-20T02:00:00Z"), event("second", "2026-08-21T02:00:00Z")]

    assert_equal "go", run_json(events).fetch("verdicts").first.fetch("verdict")
  end

  def test_rejects_an_event_without_a_timestamp
    bad = event("first", "2026-08-20T02:00:00Z")
    bad.delete("timestamp")

    result = run_json([bad])

    assert_empty result.fetch("verdicts")
    assert_match(/timestamp/, result.fetch("errors").first)
  end

  def test_does_not_make_a_patch_for_an_ambiguous_experiment
    in_repository do |repository|
      write(repository, "pricing.rb", WRAPPED + "\n" + WRAPPED.sub("class Pricing", "class OtherPricing"))

      result = run_json([event("first", "2026-08-20T02:00:00Z", "mismatches" => 1)], repository:)
      verdict = result.fetch("verdicts").first

      assert_nil verdict.fetch("patch")
      assert_equal "1 mismatches", verdict.fetch("reason")
      assert_match(/2 locations/, verdict.fetch("patch_error"))
    end
  end

  def test_reports_the_verdict_reason_and_patch_failure_separately
    [0, 2].each do |location_count|
      in_repository do |repository|
        if location_count == 2
          write(repository, "pricing.rb", WRAPPED + "\n" + WRAPPED.sub("class Pricing", "class OtherPricing"))
        end
        events = [event("first", "2026-08-20T02:00:00Z", "mismatches" => 3)]

        stdout, _stderr, _status = run_judge(repository, events)
        json_stdout, _json_stderr, _json_status = run_judge(repository, events, json: true)
        result = JSON.parse(json_stdout)
        verdict = result.fetch("verdicts").first

        assert_equal "price-v2: nogo (3 mismatches) -- no patch: the experiment has #{location_count} locations\n", stdout
        assert_equal "3 mismatches", verdict.fetch("reason")
        assert_equal "The experiment has #{location_count} locations.", verdict.fetch("patch_error")
        assert_nil verdict.fetch("patch")
      end
    end
  end

  def test_outputs_one_json_object_and_omits_experiments_without_events
    result, lines = run_json([event("first", "2026-08-20T02:00:00Z")], include_lines: true)

    assert_equal 1, lines
    assert_equal ["price-v2"], result.fetch("verdicts").map { |item| item.fetch("experiment") }
  end

  private

  def event(run_id, timestamp, overrides = {})
    {
      "run_id" => run_id,
      "experiment" => "price-v2",
      "rows_scanned" => 1500,
      "comparisons" => 1200,
      "mismatches" => 0,
      "ignored" => 0,
      "candidate_errors" => 0,
      "control_errors" => 0,
      "row_errors" => 0,
      "timestamp" => timestamp
    }.merge(overrides)
  end

  def run_json(events, config: {}, repository: nil, include_lines: false)
    operation = proc do |directory|
      write(directory, "pricing.rb", WRAPPED) unless File.exist?(File.join(directory, "pricing.rb"))
      stdout, _stderr, _status = run_judge(directory, events, config:, json: true)
      value = JSON.parse(stdout)
      include_lines ? [value, stdout.lines.length] : value
    end
    return operation.call(repository) if repository

    in_repository { |directory| return operation.call(directory) }
  end

  def in_repository
    Dir.mktmpdir("greenroom-judge") do |directory|
      git(directory, "init", "--quiet")
      yield directory
    end
  end

  def write(directory, path, content)
    absolute = File.join(directory, path)
    FileUtils.mkdir_p(File.dirname(absolute))
    File.write(absolute, content)
  end

  def run_judge(repository, events, config: {}, json: false)
    events_path = File.join(repository, "events.json")
    config_path = File.join(repository, "greenroom.yml")
    write(repository, "events.json", JSON.generate(events))
    write(repository, "greenroom.yml", config.to_yaml)
    executable = File.expand_path("../../../exe/greenroom", __dir__)
    arguments = [RbConfig.ruby, executable, "judge", "--events", events_path, "--config", config_path, "--repo", repository]
    arguments << "--json" if json
    Open3.capture3({"RUBYOPT" => nil}, *arguments, chdir: repository)
  end

  def apply(repository, patch)
    _stdout, stderr, status = Open3.capture3("git", "apply", stdin_data: patch, chdir: repository)
    assert_predicate status, :success?, stderr
  end

  def git(repository, *arguments)
    _stdout, stderr, status = Open3.capture3("git", *arguments, chdir: repository)
    raise stderr unless status.success?
  end
end
