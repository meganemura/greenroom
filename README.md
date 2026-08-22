# Greenroom

Merge the code an agent wrote, and let the night decide whether it runs.

A pull request that greenroom accepts wraps an existing method body in a
[Scientist](https://github.com/github/scientist) block and adds a candidate as
a new private method. Scientist runs no candidate by default, so the merge
changes nothing that a user can reach. A census job then calls the wrapped
method once for every row of a table, compares the old result against the new
one, and reports the counts. A judge reads those counts and opens the next
pull request: promote, revert, or retire.

```ruby
class Pricing
  def compute(order)
    Scientist.run "price-v2" do |e|
      e.use { the_original_body }
      e.try { compute_v2(order) }
      e.compare { |a, b| a == b }
    end
  end

  private

  def compute_v2(order)
    # the candidate, as a plain private method
  end
end
```

Two waits disappear. A machine reads the shape of the diff in minutes, so the
merge stops waiting for a reviewer's calendar. The census reads every row on a
schedule the team controls, so the evidence stops waiting for traffic.

## What is here

| Directory | What it holds |
|---|---|
| `gems/greenroom` | the gem a Rails application loads: the experiment methods, the recorder, the census core, and the boot assertion |
| `gems/greenroom-cli` | the `greenroom` command: `greenroom check` reads a diff and confirms the shape, `greenroom judge` reads the counts and opens the next pull request |
| `gems/rubocop-greenroom` | the cops that read one file and reject a shape an agent should not write |
| `skills` | the skills that teach the machinery |
| `docs` | the architecture and decision records |

## Status

Early. The gem is under construction, and the parts above arrive in order.

## License

MIT. See [LICENSE.txt](LICENSE.txt).
