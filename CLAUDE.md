# CLAUDE.md

Guidance for Claude Code and other coding agents working in this repository.

## Overview

Greenroom moves the risk out of a merge. A team merges agent-written Ruby
early, in a state that runs nothing new, and a nightly full-table census
decides whether the new code earns the live path.

The mechanism belongs to [Scientist](https://github.com/github/scientist).
A change wraps the existing method body in a `Scientist.run` block, puts the
candidate in a new private method, and adds nothing else. Scientist runs no
candidate by default, so the merge stays inactive. A census job then calls
the wrapped method once for every row of a table, compares the two results,
and reports the counts. A judge reads those counts and opens the next pull
request.

The name says what the room does. A candidate waits there for its turn, and
it waits until the checks turn green.

## Project rules

This repository is written for publication. Write every commit message, code
comment, README, and document in English, and write each one as though it
were already public. Rewriting history later is the expensive way to find out
that something should not have been committed.

Follow ASD-STE100 Simplified Technical English. Give one word one meaning,
write in the active voice, keep one instruction to one sentence, and keep the
articles in place.

Anything committed must make sense to a reader who has only this repository.
Do not reference working notes, task files, or conversations that a person who
clones the repository cannot read. When you want to cite one, write the
substance in place instead.

Nothing here may carry material from a private or an employer context.

Design decisions belong in `docs/` as architecture records. A new decision
gets a new record. A changed decision supersedes the old record, so the
history stays readable.

Write comments that record why: a constraint, or an alternative that got
rejected. The code already states what it does.

Do not write a claim that rests on absence: "only here", "nothing else does
this", "no other component states it". A search reports where something is,
and it never reports that you found all of it. Write the positive relation
instead, and name the file that carries it.

## Build and test commands

```bash
bin/setup                      # install the dependencies
bundle exec rake               # run the tests and the linter
bundle exec rake test          # run the tests
bundle exec rake standard      # run the linter
bundle exec rake standard:fix  # apply the fixes the linter considers safe
```

## Standing constraints

These shape the code as you write it, so they live here rather than in a
document that a reader opens later.

**The host application owns the registration.** Scientist makes a class the
process-wide default when that class includes `Scientist::Experiment`, and
Scientist skips that step for a module. Greenroom therefore ships a module
that carries methods alone, and the host writes its own class:

```ruby
class MyApp::Experiment
  include Scientist::Experiment          # the host owns this line
  include Greenroom::ExperimentBehavior  # the methods come from the gem
end
```

A gem that shipped a concrete class would take the one registration slot that
belongs to the host.

**A host that includes the greenroom module alone gets silence.** Scientist
keeps its own default, every experiment stays inactive, and each one reports
success. `Greenroom.assert_registered!` turns that silence into a sound: the
host calls it from an initializer, and it raises when the default experiment
class is still Scientist's own.

**The recorder's presence is the switch.** `enabled?` asks whether a recorder
is on the current thread. The census job puts one there, so an experiment runs
during a census and stays inactive during a request. One mechanism therefore
does two jobs: it opens the valve, and it chooses where `publish` sends the
record.

**`raised` records, and never re-raises.** Scientist's own default re-raises,
which lets a failure inside the reporting code break the call that the user
made. A method that reports an experiment must never decide whether a request
succeeds.

**Two counters, and they count different things.** The census loop counts the
rows it reads. `publish` counts the comparisons. A guard clause or an early
branch returns before the `Scientist.run` block, so the two numbers differ,
and the difference names the rows that missed the experiment. A report that
counted rows alone would call those rows checked.

**A sample carries an identifier and a digest, and never the value.** A New
Relic attribute holds 255 characters through the agent, so a sample that
carried real data would lose most of it anyway. Send one event for each
sample, and cap the number of samples that one run sends.

**Freeze each row before the call.** The candidate and the control run against
the same object, and Scientist shuffles the order of the two. A frozen row
turns a write from one side into an error that the run reports, rather than
into a mismatch that the other side inherits.

**One row must never end the night.** The census catches the error from a
single row, counts it, and continues. Sidekiq skips its `on_stop` hook when
`each_iteration` raises, so an escaping error also throws away the counts that
the segment had collected.

**New Relic sits behind a reporter.** The gem calls a small reporter
interface, and a host that uses another destination writes its own. The
`newrelic_rpm` gem stays out of the gemspec for the same reason.

**Sidekiq and Active Record sit at the edge.** The census core is plain Ruby:
it takes a target, a recorder, and a callable that wraps the read. The Sidekiq
job and the replica connection live in files that a host requires on purpose,
so the gem keeps one runtime dependency.

## Testing

The suite runs against the real Scientist gem, because the behaviour that
matters here is Scientist's own: which experiment class holds the default,
when a candidate runs, and what `publish` receives.

**Restore the default experiment class around every test that registers one.**
`include Scientist::Experiment` writes a process-wide value, so one test can
decide what a later test sees. Read the current value first, and put it back
in a `teardown`.

## Layout

The repository holds several distributable parts, so each one gets a
directory of its own.

- `gems/greenroom/`: the gem that a Rails application loads. The parts above
  live here
- `gems/greenroom-cli/`: the `greenroom` command. `greenroom check` reads a
  diff and confirms the shape. `greenroom judge` reads the counts, applies the
  thresholds, and opens the next pull request
- `gems/rubocop-greenroom/`: the cops that read one file at a time. A rule
  that a single file shows belongs here, so that the linter an agent already
  runs rejects the shape while the agent still writes it
- `skills/`: the skills that teach the greenroom machinery
- `docs/`: the architecture and decision records

Each directory under `gems/` carries its own `Gemfile`, gemspec, and Rakefile,
and `bundle exec rake` runs from inside it.

### Why the command line is a gem of its own

A person installs `greenroom-cli` on a CI runner or on a laptop, and a Rails
application loads `greenroom` in its own bundle. The two carry different
dependencies: the command reads an abstract syntax tree and talks to a metrics
service, and the library keeps a single runtime dependency so that a host
application pays for nothing it does not call.

`greenroom check` stays a command rather than a cop, because it compares the
body before the change against the body inside the `use` block. That
comparison reads two versions of one file, and a cop reads one version.

### Where a skill belongs

A skill that depends on the greenroom machinery -- the shape rules, the
census, the judge -- belongs in `skills/` here. A skill that teaches Scientist
by itself belongs with the Scientist skills instead, because a reader can use
it without any part of this repository.
