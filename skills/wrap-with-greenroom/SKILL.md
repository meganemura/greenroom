---
name: wrap-with-greenroom
description: Wrap one existing Ruby method in a Scientist experiment for a Greenroom census. Use when an equivalent refactor, upgrade, migration, or performance change must follow the Greenroom shape and pass `greenroom check` before a pull request.
---

# Wrap with Greenroom

Use this workflow for a change where the old and new implementations should return equivalent results.

Use another workflow for a new feature because it has no existing result for comparison.

Use another workflow for a write path because this workflow does not control duplicate effects.

Use another workflow for a bug fix because a correct fix should produce a mismatch for the affected input.

## Procedure

1. Select one existing method and one equivalent candidate for the experiment.

2. Keep the method signature unchanged.

3. Move the complete original method body into one `use` block without changing its expressions, names, or formatting.

4. Add the candidate as one new private method in the same class.

5. Put one `use`, one `try`, and one `compare` block in that order inside one `Scientist.run` block.

6. Make the `Scientist.run` call the complete changed method body, with those three blocks as its complete contents.

7. Keep all other existing methods, classes, modules, statements, and Ruby files unchanged in the experiment commit.

8. Put one experiment in the pull request.

9. Run `bundle exec greenroom check` to check `HEAD` before you open the pull request.

10. Run `bundle exec greenroom check <commit>` when you must check a specified commit.

11. Treat exit status `0` as acceptance and use the single rejection line to identify a failed rule.

12. Run the host RuboCop checks during the edit when the host configures `plugins: - rubocop-greenroom`.

## Accepted shape

Use this structure and replace the example names and candidate body:

```ruby
class Pricing
  def compute(order)
    Scientist.run "price-v2" do |experiment|
      experiment.use { order.subtotal * rate(order) }
      experiment.try { compute_v2(order) }
      experiment.compare { |control, candidate| control == candidate }
    end
  end

  private

  def compute_v2(order)
    order.subtotal * new_rate(order)
  end
end
```

The `use` block contains the complete old body.

The `try` block calls the new private method.

The `compare` block defines result equality.

## Unsafe constructs

Reject a `return` inside a `use` or `try` block because it can leave the outer method before comparison and publication.

Reject a `binding` inside a `use` or `try` block because its local-variable view changes after the wrap.

A `return` inside a lambda keeps its lambda behavior.

A `return` inside a proc or an ordinary block keeps the unsafe behavior because it leaves the outer method.

The wrap preserves the behavior of `yield`, a method-level `rescue` or `ensure`, `__method__`, local variables, and constant references.

## After the merge

Scientist keeps the candidate inactive by default after the experiment merges.

The nightly census calls both implementations for every row and records the comparison counts.

The judge reads those counts and creates the next pull request.

The experiment wrap and the candidate cutover therefore belong in separate pull requests.
