# 2. Let the recorder's presence enable the experiment

Date: 2026-08-22

## Status

Accepted.

## Context

Two questions arrive together. When does a candidate run? And where does
`publish` send what it observes?

The first version answered them separately: a flag decided whether the
experiment ran, and a second condition decided the destination. Two
conditions that must agree can disagree.

A census run needs the experiment active. A user's request, in the first
version of greenroom, does not.

## Decision

`enabled?` asks one question: is a recorder on the current thread?

The census job puts a recorder there before it reads the first row, and takes
it away when the run stops. `publish` asks the same question again, and sends
to the recorder when one is present, or sends one event immediately when none
is.

## Consequences

One mechanism opens the valve and chooses the destination, so the two cannot
disagree.

A request runs no candidate, because nothing puts a recorder on a request's
thread.

A host that wants an experiment during a request overrides `enabled?` in its
own class, which is a plain Ruby method. The immediate-send path in `publish`
serves that host.

The thread-local recorder is the one ambient value in this design. The branch
inside `publish` stays an ordinary `if`, which a reader can follow.
