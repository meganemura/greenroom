# 5. Separate the command line from the library

Date: 2026-08-22

## Status

Superseded by [ADR 7](0007-ship-the-command-inside-the-library-gem.md).

## Context

Greenroom has parts that run in three places. A Rails application loads
methods that an experiment calls. A pull request check reads a diff. A
nightly job reads counts and opens the next pull request.

The parts that read a diff and read counts began as scripts in a `tools`
directory that CI would clone and run.

## Decision

The parts that a person invokes become subcommands of one executable, and that
executable ships as `greenroom-cli`:

```
greenroom check   # read a diff, and confirm the shape
greenroom judge   # read the counts, and open the next pull request
```

The repository therefore holds three gems: `greenroom` for the library,
`greenroom-cli` for the command, and `rubocop-greenroom` for the cops.

## Consequences

A person installs the command on a CI runner or on a laptop, rather than
cloning a repository to run a script.

The library keeps one runtime dependency. `greenroom check` reads an abstract
syntax tree and `greenroom judge` talks to a metrics service and to a source
host, and a host application pays for none of that.

The cops stay in a third gem, because RuboCop loads a plugin through its own
configuration rather than through a command.

`greenroom check` stays a command rather than a cop. It confirms that the
original method body reached the `use` block unchanged, which reads the
version before the change and the version after it. A cop reads one version.
