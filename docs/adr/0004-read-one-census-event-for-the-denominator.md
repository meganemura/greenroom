# 4. Read one census event for the denominator

Date: 2026-08-22

## Status

Accepted.

## Context

A census run sends three kinds of event. One reports the totals for the run,
one reports progress while the run is alive, and one carries a mismatch
sample.

Samples repeat when a run resumes, because the cursor leaves them out
([ADR 3](0003-carry-the-counters-in-the-iteration-cursor.md)). Progress events
repeat for the same reason: each execution sends one.

The judge decides whether an experiment gets promoted, reverted, or retired,
and it decides from counts.

## Decision

The judge reads `GreenroomCensus` for every count it uses. That event arrives
once for a run, from the `on_complete` hook.

`GreenroomCensusProgress` says that a run is alive, and points at the samples
that a revert pull request quotes. It never contributes to a count.

A run sends `GreenroomCensus` even when no comparison happened. The event
carries `comparisons` as zero and `rows_scanned` as the real number.

The judge decides "not enough evidence" from a `GreenroomCensus` whose
denominator sits under the floor. It never decides anything from a missing
event.

## Consequences

The two numbers that a report separates -- rows read, and comparisons reached
-- both arrive in one event, so their difference stays readable. That
difference names the rows that returned before reaching the experiment.

A misconfigured host produces a visible zero rather than silence. A judge that
inferred failure from a missing event would be reading absence, and a search
reports where something is rather than that you found all of it.

A missing event still means something, and it means that the run did not
happen. Sidekiq Enterprise runs a periodic job without backfilling a missed
night, so a night with no event is a night that did not run.
