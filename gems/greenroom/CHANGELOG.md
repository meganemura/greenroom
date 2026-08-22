## [Unreleased]

## [0.1.0] - 2026-08-22

- Add `Greenroom::ExperimentBehavior`, the `enabled?`, `publish`, and `raised`
  methods a host mixes into its own Scientist experiment class.
- Add `Greenroom::Recorder`, which counts rows, comparisons, mismatches, and
  errors for a run, and carries its counts through an interruption.
- Add the census core: `Greenroom::Census::Run`, `Cursor`, `Job`, and
  `Middleware`.
- Add `Greenroom.assert_registered!`, which fails at boot when no class has
  registered with Scientist.
- Add `greenroom check`, which reads a commit and confirms that the original
  method body reached the `use` block unchanged.
- Add `greenroom judge`, which reads census counts and returns a verdict and a
  patch.
