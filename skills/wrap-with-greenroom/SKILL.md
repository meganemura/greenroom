---
name: wrap-with-greenroom
description: Wrap all or part of one existing Ruby method in a Scientist experiment for a Greenroom census. Use for an equivalent refactor, upgrade, migration, or performance change that must pass `greenroom check`.
---

# Wrap with Greenroom

Use this procedure when the old and new implementations must return equivalent results.

This procedure cannot evaluate a new feature because the feature has no existing result for comparison.

Do not use this procedure for a write path because the experiment can duplicate side effects.

Do not use this procedure for a bug fix because the correct fix must produce a mismatch for the affected input.

## Procedure

1. Select one existing method and one equivalent candidate for the experiment.

2. Keep the method signature unchanged.

3. Select one consecutive group of original statements for the `use` block.

4. Keep each original statement before and after that group unchanged.

5. Move the selected statements into one `use` block without changing their expressions, names, or formatting.

6. Add the candidate as one new private method in the same class.

7. Put one `use`, one `try`, and one `compare` block in that order inside one `Scientist.run` block.

8. Use the `Scientist.run` call as the single statement between the unchanged prefix and suffix.

9. Assign the result of `Scientist.run` when an unchanged suffix uses the wrapped value.

10. Keep all other existing methods, classes, modules, statements, and Ruby files unchanged in the experiment commit.

11. Put one experiment in the pull request.

12. Run `bundle exec greenroom check` to check `HEAD` before you open the pull request.

13. Run `bundle exec greenroom check <commit>` when you must check a specified commit.

14. Treat exit status `0` as acceptance and use the single rejection line to identify a failed rule.

15. Run the host RuboCop checks during the edit when the host configures `plugins: - rubocop-greenroom`.

## Accepted shapes

The original method can contain an unchanged guard clause before the experiment:

```ruby
class Calculator
  def compute(o)
    return 0 if o.nil?
    Scientist.run "double-v2" do |experiment|
      experiment.use { o * 2 }
      experiment.try { compute_v2(o) }
      experiment.compare { |control, candidate| control == candidate }
    end
  end

  private

  def compute_v2(o)
    o + o
  end
end
```

The original method can use the experiment result in an unchanged suffix:

```ruby
class Calculator
  def compute(o)
    value = Scientist.run "double-v2" do |experiment|
      experiment.use { o * 2 }
      experiment.try { compute_v2(o) }
      experiment.compare { |control, candidate| control == candidate }
    end
    value.round(2)
  end

  private

  def compute_v2(o)
    o + o
  end
end
```

The `use` block contains the unchanged statements from the selected part of the old body.

The `try` block calls the new private method.

The `compare` block defines result equality.

Do not put the `Scientist.run` call inside an `if` statement.

Do not assign the `Scientist.run` result through multiple assignment.

## Unsafe constructs

Reject a `return` in statements that move into a `use` or `try` block.

That `return` can leave the outer method before the comparison and publication.

A `return` in an unchanged prefix or suffix remains safe because it still returns from the same method.

A `return` inside a lambda keeps its lambda behavior.

A `return` inside a proc or an ordinary block keeps the unsafe behavior because it leaves the outer method.

Reject a `binding` inside a `use` or `try` block because its local-variable view changes after the wrap.

The wrap preserves the behavior of `yield`, a method-level `rescue` or `ensure`, `__method__`, local variables, and constant references.

## After the merge

Scientist keeps the candidate inactive by default after the experiment merges.

The nightly census calls both implementations for every row and records the comparison counts.

The judge reads those counts and creates the next pull request.

The experiment wrap and the candidate cutover therefore belong in separate pull requests.
