# rubocop-greenroom

`rubocop-greenroom` reports structural problems that RuboCop can identify from one Ruby file.

Add the plugin to the host application's `.rubocop.yml`:

```yaml
plugins:
  - rubocop-greenroom
```

The plugin enables three cops:

- `Greenroom/ScienceBlockShape` requires one `use`, one `try`, and one `compare` call in that order.
- `Greenroom/UnsafeScienceBody` reports unsafe `return` and `binding` expressions in `use` and `try` bodies.
- `Greenroom/CandidateIsPrivate` reports a visible same-class candidate definition that is public or protected.

These cops inspect one file. A separate diff checker verifies that a `use` body preserves the previous method body.
