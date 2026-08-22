# 1. Ship a module, and let the host register the experiment class

Date: 2026-08-22

## Status

Accepted.

## Context

Scientist needs one experiment class that implements `enabled?` and
`publish`. It finds that class through a process-wide value:
`Scientist::Experiment.included` calls `set_default(base)`, and
`Scientist::Experiment.new(name)` returns an instance of whatever class
registered last.

That call runs only when the includer is a class. Scientist skips it for a
module, and the Scientist README states the same rule.

Greenroom could ship a class that a host inherits, or a module that a host
includes.

## Decision

Greenroom ships `Greenroom::ExperimentBehavior`, a module that carries
`enabled?`, `publish`, and `raised`. The host writes the class:

```ruby
class MyApp::Experiment
  include Scientist::Experiment          # the host owns this line
  include Greenroom::ExperimentBehavior  # the methods come from the gem
end
```

We rejected a variant where the greenroom module's `included` hook calls
`base.include Scientist::Experiment`, which would save the host one line. A
hook inside a hook hides the registration at the moment a reader most needs to
see it.

## Consequences

The registration slot stays with the host, which is the party that knows
whether it already has an experiment class.

A host that includes the greenroom module alone gets silence: Scientist keeps
its own default, and every experiment reports success while running no
candidate. `Greenroom.assert_registered!` exists to answer that, and
[ADR 4](0004-read-one-census-event-for-the-denominator.md) describes the
operational half of the answer.

A test that defines a class including `Scientist::Experiment` changes the
value for the whole process. Each such test reads the current value first and
puts it back afterwards.
