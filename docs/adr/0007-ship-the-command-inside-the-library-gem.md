# 7. Ship the command inside the library gem

Date: 2026-08-22

## Status

Accepted. Supersedes
[ADR 5](0005-separate-the-command-line-from-the-library.md).

## Context

ADR 5 put the `greenroom` command in a gem of its own, to keep the library's
runtime dependencies down to one. A Rails application loads the library, and
the command reads an abstract syntax tree, which the application never needs.

That reasoning missed who runs the command. `greenroom check` reads a commit
in the repository of the application that loads the library, and it runs in
that repository's CI, inside that repository's bundle. A separate gem asks the
same project to install greenroom twice, and asks this repository to carry a
second gemspec, a second lockfile, and a second release.

## Decision

The `greenroom` command ships in the greenroom gem, as `exe/greenroom`, with
`check` as its first subcommand. `bundle exec greenroom check` then works in
CI with nothing further installed.

`rubocop-ast` becomes a second runtime dependency, and the command loads it
when it runs rather than when the library loads. `lib/greenroom.rb` requires
nothing from the command, so an application that boots this gem never parses
Ruby it does not intend to parse.

The cops stay in `rubocop-greenroom`, which ADR 5 already separated for a
different reason: RuboCop loads a plugin through its own configuration, and
that plugin belongs to whoever runs RuboCop rather than to whoever runs the
application.

## Consequences

An application that loads greenroom resolves `rubocop-ast` as well. That is
the real cost, and it buys the command working wherever the library already
does.

Loading stays lazy, so the parser reaches memory only in a process that runs
the command.

`greenroom check` still stays a command rather than a cop. It compares the
method body before a change against the body inside the `use` block, which
reads two versions of one file, and a cop reads one version. That part of
ADR 5 survives it.
