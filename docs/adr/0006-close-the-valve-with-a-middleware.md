# 6. Close the valve with a middleware, and say so when it is absent

Date: 2026-08-22

## Status

Accepted.

## Context

A recorder on the current thread enables the experiment
([ADR 2](0002-let-the-recorder-presence-enable-the-experiment.md)). The census
job puts one there, and takes it away when the run stops.

Sidekiq's iterable job takes it away in the `on_stop` hook, and Sidekiq calls
that hook after the iteration returns. An error that escapes `each_iteration`
returns nothing: it propagates out of `perform`, and `on_stop` does not run.

Sidekiq gives a thread to one job and then to the next. A recorder that
survives its own job therefore sits on the thread while an unrelated job runs,
and `enabled?` answers true inside that job. Candidates run in a place that
this design promises to keep them out of, which is the one safety property
version 1 offers.

Wrapping `perform` would close this, and Sidekiq refuses it: the iterable
mixin defines `method_added` to raise when a job defines `perform`.

## Decision

Greenroom ships `Greenroom::Census::Middleware`, a Sidekiq server middleware
that clears the thread in an `ensure` block. A host adds it to the server
middleware chain.

A census job asserts, before it reads a row, that the middleware sits in the
chain. It raises and runs nothing when the middleware is absent.
`Sidekiq::Middleware::Chain#exists?` answers that question.

The job also clears the thread before it installs its own recorder. That
second guard keeps one census run from inheriting another's recorder, and it
replaces nothing: a host that skips the middleware still leaks into the jobs
between two census runs.

## Consequences

The valve closes on every path out of a job, including the paths that reach an
error.

A host that forgets to register the middleware learns at the first run rather
than through candidates that run where nobody expected them. The failure that
this turns audible is the same shape as the one
[ADR 1](0001-ship-a-module-and-let-the-host-register.md) turns audible: a
missing line of host configuration that otherwise produces a green face and
wrong behaviour.

Registration is one more line that a host writes. The gem's README carries it
beside the experiment class and the boot assertion, so a reader meets all
three configuration lines in one place.
