# 3. Carry the counters in the iteration cursor

Date: 2026-08-22

## Status

Accepted.

## Context

A census reads every row of a table, so a run outlives a deploy. Sidekiq's
iterable job answers that: it saves a cursor to Redis, raises `Interrupted` on
shutdown, and re-enqueues the job under the same job id.

The recorder holds its counters in memory. A resumed run therefore starts with
empty counters while the cursor points into the middle of the table.

Two answers were available.

The first sends one event for each execution and asks the judge to add them
up. The counts survive, but a run that fails inside `each_iteration` retries
from the last saved cursor, so the rows between that cursor and the failure
get counted twice. The judge cannot see the overlap.

The second saves the counters next to the position.

## Decision

The cursor carries both:

```ruby
{"position" => the_original_cursor, "counts" => recorder.snapshot}
```

`Greenroom::Census::Cursor.decorate` wraps the enumerator the host builds and
pairs each yielded cursor with a snapshot of the counters. Sidekiq's iteration
reads a cursor from the enumerator, so the enumerator is the part that decides
what a cursor holds.

The timing is what makes this correct. Sidekiq assigns the cursor when the
enumerator yields row N, and it runs `each_iteration` for row N afterwards. A
snapshot taken at the yield therefore counts rows 1 to N-1, and a resume
starts at row N. The position and the counters describe the same moment.

The decoration must stay lazy. `Enumerator.new` reads the recorder at each
yield, and a version that built the pairs in advance would save counters from
the wrong moment.

## Consequences

A re-processed row is counted once, and the same holds after a failure:
Sidekiq calls `flush_state` before it re-raises an error from
`each_iteration`, so a retry resumes from a position whose counters match it.

The judge reads one event for a run rather than adding up segments. See
[ADR 4](0004-read-one-census-event-for-the-denominator.md).

The recorder is built in `build_enumerator` rather than in `on_start`, because
Sidekiq calls `build_enumerator` first.

A cursor travels through JSON, so it holds JSON values alone, and hash keys
return as strings.

Mismatch samples stay out of the cursor. A run holds up to one hundred of
them, and Redis would carry that for every census. A sample is evidence rather
than a denominator, so a repeated sample after a resume costs nothing that
matters.
