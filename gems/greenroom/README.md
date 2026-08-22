# Greenroom

Turn a [Scientist](https://github.com/github/scientist) experiment into
evidence, without running the candidate on a live request.

An experiment stays inactive by default: `Scientist::Default#enabled?`
returns false, so the candidate never runs and `publish` never sends
anything. A nightly census job installs a recorder for the duration of its
run. While that recorder is installed, the experiment turns on and the
recorder counts every comparison. The run ends with one aggregate event,
plus a limited number of mismatch samples. A sample carries a row
identifier and a digest of the value, never the value itself.

## What this gem provides

- `Greenroom::ExperimentBehavior`, a module with the `enabled?`, `publish`,
  and `raised` methods a Scientist experiment class needs.
- `Greenroom::Recorder`, the thread-local counter a census job installs and
  removes around its run.
- `Greenroom::Census::Run`, the per-row work a census job performs, plus
  `Greenroom::Census::Job`, a thin `Sidekiq::IterableJob` wrapper around it.
- `Greenroom.assert_registered!`, a boot-time check for one common
  misconfiguration (see below).
- `Greenroom::Reporter`, the seam between a recorded event and wherever it
  is sent. The gem ships `Reporter::Null` (the default, does nothing) and
  `Reporter::Memory` (collects events, for tests). A New Relic adapter
  lives in `greenroom/reporter/new_relic`, a separate file a host requires
  on purpose.

## Setup

A host application writes three things.

### 1. An experiment class

`Scientist::Experiment` allows exactly one class per process to register
as the default; a later `include` silently takes that slot from an
earlier one. Because of this, `ExperimentBehavior` ships as a module, not
a class: the host's own class claims the slot, and the gem never competes
for it.

```ruby
class Pricing::Experiment
  include Scientist::Experiment          # registers this class with Scientist
  include Greenroom::ExperimentBehavior  # adds enabled?, publish, raised

  attr_reader :name

  def initialize(name)
    @name = name
  end
end
```

Include `Scientist::Experiment` first. `ExperimentBehavior#raised` must
come later in the ancestor chain than `Scientist::Experiment#raised` (the
one that re-raises) to actually override it; including the two in the
other order would leave every internal failure re-raised into the caller.

`Scientist.run("price-v2") { |e| ... }` and `Scientist::Experiment.new(name)`
both look up the registered class, so the rest of a host's code calls
Scientist exactly as the [Scientist README](https://github.com/github/scientist)
describes; nothing else changes.

### 2. A boot-time check

A host that includes only `ExperimentBehavior`, and forgets
`Scientist::Experiment`, gets no error: `enabled?` and `publish` both
exist, but `Scientist::Experiment.new` still returns the inert
`Scientist::Default`, so every experiment reports success while running no
candidate, forever. Call this once at boot to turn that silent
misconfiguration into a startup failure instead:

```ruby
# config/initializers/greenroom.rb
Greenroom.assert_registered!
```

### 3. A Sidekiq server middleware

A census job installs a recorder before it reads the first row and removes
it when the run stops. If a row raises an exception that escapes
`each_iteration`, Sidekiq skips the job's `on_stop` hook entirely, so that
removal never happens. Sidekiq also reuses worker threads across jobs, so
the next, unrelated job on that thread would otherwise find an experiment
already turned on. Add this middleware to close that gap on every path out
of a job, including the ones that hit an error:

```ruby
# config/initializers/sidekiq.rb
Sidekiq.configure_server do |config|
  config.server_middleware do |chain|
    chain.add Greenroom::Census::Middleware
  end
end
```

## Writing a census target

A census job reads rows through a small target object that answers three
questions: which experiment it feeds, which rows to read, and how to call
one row.

```ruby
class PriceV2Census
  def experiment = "price-v2"
  def scope = Order.all
  def call(order) = Pricing.new(order).compute
end
```

`Greenroom::Census::Run#visit(row)` freezes the row, counts it, tells the
recorder which row is under examination, and calls the target through a
`reader` -- `Greenroom::Census::Reader::Direct` by default, which just
calls the block. A host reading from a database replica supplies its own
reader with the same one-method interface; this gem does not ship a
replica-reading implementation.

`Greenroom::Census::Job` wires a target's `reader` and `each_iteration`
into `Sidekiq::IterableJob`, installs and restores a `Greenroom::Recorder`
keyed on the job's `jid`, and sends the `GreenroomCensusProgress` and
`GreenroomCensus` events described below from `on_stop` and `on_complete`.
Its default `row_enumerator` reads through Sidekiq's own
`active_record_records_enumerator`, so a target whose `scope` is an
ActiveRecord relation needs nothing beyond `target(*args)`; a host whose
target's `scope` is something else (an array, a CSV) overrides
`row_enumerator` instead.

## Events

| Name | Sent from | Carries |
|---|---|---|
| `GreenroomComparison` | `ExperimentBehavior#publish`, when no recorder is installed | one comparison's outcome |
| `GreenroomInternalError` | `ExperimentBehavior#raised` | the operation and exception class that failed inside this gem's own instrumentation |
| `GreenroomCensusProgress` | `Recorder#flush_segment` | a sign that the run is still alive, and any mismatch samples gathered so far |
| `GreenroomMismatch` | `Recorder#flush_segment`, one per sample | a row identifier and digests, never the value itself |
| `GreenroomCensus` | `Recorder#flush_total` | the run's full counts: `rows_scanned`, `comparisons`, `mismatches`, `ignored`, `candidate_errors`, `control_errors`, `row_errors` |

A judge reads `comparisons` and the other counts from `GreenroomCensus`
alone, never from `GreenroomCensusProgress`. A run sends exactly one
`GreenroomCensus` event, even when it triggered zero comparisons: the
event's presence, with `comparisons` at zero, is how a reader tells "ran
and found nothing to compare" apart from "did not run at all".
