# frozen_string_literal: true

require "test_helper"

class Greenroom::RecorderTest < Minitest::Test
  include Greenroom::ResetsGlobalState

  # Builds a `Scientist::Result` directly from observations, the way
  # `Scientist::Experiment#generate_result` does internally, instead of
  # going through `Experiment#run`. `run` only compares control and
  # candidate when `enabled?` is true, and making a class enabled would mean
  # registering it as the process-wide default (`Scientist::Experiment`
  # allows exactly one). Building the `Result` directly gets a real,
  # unfrozen-until-construction object for `Recorder#record` to consume
  # without touching that global.
  def build_result(control:, candidate:, name: "test")
    experiment = Scientist::Default.new(name)
    control_observation = Scientist::Observation.new("control", experiment, &control)
    candidate_observation = Scientist::Observation.new("candidate", experiment, &candidate)
    Scientist::Result.new(experiment, [control_observation, candidate_observation], control_observation)
  end

  def matched_result(name: "test")
    build_result(name: name, control: -> { 1 }, candidate: -> { 1 })
  end

  def mismatched_result(name: "test")
    build_result(name: name, control: -> { 1 }, candidate: -> { 2 })
  end

  def candidate_raised_result(name: "test")
    build_result(name: name, control: -> { 1 }, candidate: -> { raise "boom" })
  end

  def control_raised_result(name: "test")
    build_result(name: name, control: -> { raise "boom" }, candidate: -> { 1 })
  end

  # -- install / current / uninstall / with -----------------------------

  def test_current_is_nil_when_nothing_is_installed
    assert_nil Greenroom::Recorder.current
  end

  def test_install_makes_the_recorder_the_current_one
    recorder = Greenroom::Recorder.new(run_id: "r1")

    Greenroom::Recorder.install(recorder)

    assert_same recorder, Greenroom::Recorder.current
  end

  def test_uninstall_clears_current_and_returns_the_uninstalled_recorder
    recorder = Greenroom::Recorder.new(run_id: "r1")
    Greenroom::Recorder.install(recorder)

    uninstalled = Greenroom::Recorder.uninstall

    assert_same recorder, uninstalled
    assert_nil Greenroom::Recorder.current
  end

  def test_with_installs_for_the_duration_of_the_block_and_uninstalls_after
    recorder = Greenroom::Recorder.new(run_id: "r1")

    seen_inside = nil
    Greenroom::Recorder.with(recorder) { seen_inside = Greenroom::Recorder.current }

    assert_same recorder, seen_inside
    assert_nil Greenroom::Recorder.current
  end

  def test_with_uninstalls_even_if_the_block_raises
    recorder = Greenroom::Recorder.new(run_id: "r1")

    assert_raises(RuntimeError) do
      Greenroom::Recorder.with(recorder) { raise "boom" }
    end

    assert_nil Greenroom::Recorder.current
  end

  def test_install_is_thread_local_not_shared_across_threads
    # A census job processes one row per thread; the thread is the unit that
    # must see its own recorder and no other thread's, so `Thread.current`
    # (fiber-local by default) is the right scope. A process-global would
    # leak one job's recorder into a concurrently running, unrelated job.
    recorder = Greenroom::Recorder.new(run_id: "r1")
    Greenroom::Recorder.install(recorder)

    seen_in_other_thread = Thread.new { Greenroom::Recorder.current }.value

    assert_nil seen_in_other_thread
    assert_same recorder, Greenroom::Recorder.current
  end

  # -- count_row / rows_scanned / record_row_error -----------------------

  def test_count_row_increments_rows_scanned
    recorder = Greenroom::Recorder.new(run_id: "r1")

    3.times { recorder.count_row }

    assert_equal 3, recorder.rows_scanned
  end

  # -- record: the four comparison shapes (matched, mismatched, candidate
  #    raised, control raised) --------------------------------------------

  def test_record_counts_a_matched_comparison
    recorder = Greenroom::Recorder.new(run_id: "r1")

    recorder.record(matched_result)

    tally = recorder.tallies.fetch("test")
    assert_equal 1, tally.comparisons
    assert_equal 0, tally.mismatches
    assert_equal 0, tally.ignored
    assert_equal 0, tally.candidate_errors
    assert_equal 0, tally.control_errors
  end

  def test_record_counts_a_mismatched_comparison
    recorder = Greenroom::Recorder.new(run_id: "r1")

    recorder.record(mismatched_result)

    tally = recorder.tallies.fetch("test")
    assert_equal 1, tally.comparisons
    assert_equal 1, tally.mismatches
    assert_equal 0, tally.ignored
  end

  def test_record_counts_a_candidate_exception
    recorder = Greenroom::Recorder.new(run_id: "r1")

    recorder.record(candidate_raised_result)

    tally = recorder.tallies.fetch("test")
    assert_equal 1, tally.comparisons
    assert_equal 1, tally.candidate_errors
    assert_equal 0, tally.control_errors
  end

  def test_record_counts_a_control_exception
    recorder = Greenroom::Recorder.new(run_id: "r1")

    recorder.record(control_raised_result)

    tally = recorder.tallies.fetch("test")
    assert_equal 1, tally.comparisons
    assert_equal 1, tally.control_errors
    assert_equal 0, tally.candidate_errors
  end

  def test_record_counts_ignored_mismatches_separately_from_mismatches
    experiment = Scientist::Default.new("test")
    experiment.ignore { |_control, _candidate| true }
    control_observation = Scientist::Observation.new("control", experiment) { 1 }
    candidate_observation = Scientist::Observation.new("candidate", experiment) { 2 }
    result = Scientist::Result.new(experiment, [control_observation, candidate_observation], control_observation)

    recorder = Greenroom::Recorder.new(run_id: "r1")
    recorder.record(result)

    tally = recorder.tallies.fetch("test")
    assert_equal 1, tally.ignored
    assert_equal 0, tally.mismatches
  end

  # -- experiment: pre-seeds a zero tally ---------------------------------

  def test_experiment_option_preseeds_a_zero_tally
    recorder = Greenroom::Recorder.new(run_id: "r1", experiment: "price-v2")

    tally = recorder.tallies.fetch("price-v2")
    assert_equal 0, tally.comparisons
    assert_equal 0, tally.mismatches
  end

  # -- samples: limit, shape, and no raw data -----------------------------

  def test_samples_are_recorded_only_for_mismatches
    recorder = Greenroom::Recorder.new(run_id: "r1")

    recorder.record(matched_result)
    recorder.record(mismatched_result)

    assert_equal 1, recorder.samples.size
  end

  def test_samples_do_not_exceed_sample_limit
    recorder = Greenroom::Recorder.new(run_id: "r1", sample_limit: 2)

    5.times { recorder.record(mismatched_result) }

    assert_equal 2, recorder.samples.size
  end

  def test_sample_carries_subject_and_digests_but_never_the_raw_value
    recorder = Greenroom::Recorder.new(run_id: "r1")
    recorder.subject = 42

    recorder.record(mismatched_result)

    sample = recorder.samples.first
    assert_equal "r1", sample[:run_id]
    assert_equal "test", sample[:experiment]
    assert_equal 42, sample[:subject]
    assert_equal Greenroom::Digest.of(1), sample[:control_digest]
    assert_equal Greenroom::Digest.of(2), sample[:candidate_digest]
    assert_nil sample[:control_error]
    assert_nil sample[:candidate_error]
    refute_includes sample.values.map(&:to_s), "1"
    refute_includes sample.values.map(&:to_s), "2"
  end

  def test_sample_carries_the_exception_class_name_but_never_the_message
    recorder = Greenroom::Recorder.new(run_id: "r1")

    recorder.record(candidate_raised_result)

    sample = recorder.samples.first
    assert_equal "RuntimeError", sample[:candidate_error]
    refute_includes sample.values.compact.map(&:to_s), "boom"
  end

  # -- snapshot / restore ---------------------------------------------------

  def test_snapshot_is_json_round_trippable_and_restore_reproduces_the_counts
    require "json"

    recorder = Greenroom::Recorder.new(run_id: "r1", experiment: "price-v2")
    recorder.count_row
    recorder.count_row
    recorder.record(mismatched_result(name: "price-v2"))
    recorder.record_row_error(RuntimeError.new("boom"))

    round_tripped = JSON.parse(JSON.generate(recorder.snapshot))

    restored = Greenroom::Recorder.new(run_id: "r1")
    restored.restore(round_tripped)

    assert_equal recorder.rows_scanned, restored.rows_scanned
    original_tally = recorder.tallies.fetch("price-v2")
    restored_tally = restored.tallies.fetch("price-v2")
    assert_equal original_tally.comparisons, restored_tally.comparisons
    assert_equal original_tally.mismatches, restored_tally.mismatches
  end

  def test_restore_keeps_the_seeded_tally_when_the_snapshot_does_not_name_it
    # `Recorder.new(experiment:)` seeds a zero tally under that name (see
    # the comment in `initialize`), before a resumed segment's `restore`
    # ever runs. A snapshot taken before the first comparison for that name
    # does not carry it -- `restore` must keep the seeded zero rather than
    # erase it, or the run's later `flush_total` would report
    # `experiment: nil` instead of the name it is actually comparing.
    recorder = Greenroom::Recorder.new(run_id: "r1", experiment: "price-v2")

    recorder.restore({"rows_scanned" => 3, "tallies" => {}})

    tally = recorder.tallies.fetch("price-v2")
    assert_equal 0, tally.comparisons
    assert_equal 3, recorder.rows_scanned
  end

  def test_restore_overwrites_a_tally_the_snapshot_does_name
    recorder = Greenroom::Recorder.new(run_id: "r1", experiment: "price-v2")

    recorder.restore({"tallies" => {"price-v2" => {"comparisons" => 4, "mismatches" => 1}}})

    tally = recorder.tallies.fetch("price-v2")
    assert_equal 4, tally.comparisons
    assert_equal 1, tally.mismatches
  end

  def test_snapshot_does_not_include_samples
    recorder = Greenroom::Recorder.new(run_id: "r1")
    recorder.record(mismatched_result)

    refute recorder.snapshot.key?("samples")
    refute recorder.snapshot.key?(:samples)
  end

  # -- flush_segment / flush_total: event kinds and counts -----------------

  def test_flush_segment_sends_one_progress_event_and_one_mismatch_event_per_sample
    reporter = Greenroom::Reporter::Memory.new
    recorder = Greenroom::Recorder.new(run_id: "r1", experiment: "price-v2")
    recorder.record(mismatched_result(name: "price-v2"))
    recorder.record(mismatched_result(name: "price-v2"))

    recorder.flush_segment(reporter)

    types = reporter.events.map(&:type)
    assert_equal 1, types.count("GreenroomCensusProgress")
    assert_equal 2, types.count("GreenroomMismatch")
  end

  def test_flush_segment_discards_samples_that_were_already_sent
    reporter = Greenroom::Reporter::Memory.new
    recorder = Greenroom::Recorder.new(run_id: "r1")
    recorder.record(mismatched_result)

    recorder.flush_segment(reporter)

    assert_equal 0, recorder.samples.size
  end

  def test_flush_total_sends_exactly_one_census_event_when_one_experiment_ran
    reporter = Greenroom::Reporter::Memory.new
    recorder = Greenroom::Recorder.new(run_id: "r1", experiment: "price-v2")
    recorder.count_row
    recorder.record(mismatched_result(name: "price-v2"))

    recorder.flush_total(reporter)

    census_events = reporter.events.select { |event| event.type == "GreenroomCensus" }
    assert_equal 1, census_events.size
    attributes = census_events.first.attributes
    assert_equal "r1", attributes[:run_id]
    assert_equal "price-v2", attributes[:experiment]
    assert_equal 1, attributes[:rows_scanned]
    assert_equal 1, attributes[:comparisons]
    assert_equal 1, attributes[:mismatches]
    assert_equal 0, attributes[:ignored]
    assert_equal 0, attributes[:candidate_errors]
    assert_equal 0, attributes[:control_errors]
    assert_equal 0, attributes[:row_errors]
  end

  # -- a run with zero comparisons must still produce one census event -----

  def test_flush_total_sends_one_event_with_zero_comparisons_when_none_ran
    # A misconfigured host -- one that includes only `ExperimentBehavior`,
    # never `Scientist::Experiment` -- runs zero comparisons for the whole
    # night. Without this event, a judge cannot tell "zero comparisons" from
    # "the job never ran"; the event's presence, not its absence, is what a
    # judge checks.
    reporter = Greenroom::Reporter::Memory.new
    recorder = Greenroom::Recorder.new(run_id: "r1", experiment: "price-v2")
    5.times { recorder.count_row }

    recorder.flush_total(reporter)

    census_events = reporter.events.select { |event| event.type == "GreenroomCensus" }
    assert_equal 1, census_events.size
    attributes = census_events.first.attributes
    assert_equal 0, attributes[:comparisons]
    assert_equal 5, attributes[:rows_scanned]
  end

  def test_flush_total_sends_one_event_with_a_nil_experiment_when_no_name_was_given
    reporter = Greenroom::Reporter::Memory.new
    recorder = Greenroom::Recorder.new(run_id: "r1")
    3.times { recorder.count_row }

    recorder.flush_total(reporter)

    census_events = reporter.events.select { |event| event.type == "GreenroomCensus" }
    assert_equal 1, census_events.size
    attributes = census_events.first.attributes
    assert_nil attributes[:experiment]
    assert_equal 3, attributes[:rows_scanned]
  end
end
