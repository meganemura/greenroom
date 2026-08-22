## [Unreleased]

## [0.1.0] - 2026-08-22

- Add `Greenroom/ScienceBlockShape`, which requires `use`, `try`, and
  `compare` once each and in that order inside a `Scientist.run` block.
- Add `Greenroom/UnsafeScienceBody`, which reports a `return` or a `binding`
  that moves into a `use` or `try` block.
- Add `Greenroom/CandidateIsPrivate`, which requires the method a `try` block
  calls to be private when the same file defines it.
- Ship the cops as a lint_roller plugin, so a host adds them through the
  `plugins` key of its RuboCop configuration.
