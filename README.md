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

## Why not Scientist alone

Scientist runs the old and candidate paths, compares their results, and
publishes an observation. A team must still choose the evidence source, the
execution context, and the decision process.

Live traffic supplies evidence in a typical Scientist setup. A cold path can
take months to produce enough observations. The candidate also runs inside the
live request when the experiment is enabled. Scientist publishes the data, and
a person decides what to do with it.

Greenroom adds a nightly census that compares both paths for every target row.
Evidence then follows a controlled schedule instead of traffic volume or luck.
The census counts every scanned row and every comparison, and keeps the two
apart. Their difference names the rows that a guard clause returned before they
reached the experiment. It prevents an empty inspection from looking like a
clean result.

`greenroom check` inspects the diff shape and decides whether an automatic merge
is safe. `greenroom judge` classifies the counts and creates an applicable patch
for the next pull request.

Scientist already ships experiments disabled by default because
`Scientist::Default#enabled?` returns false. Greenroom changes how an application
enables them. Its `enabled?` method returns true when the current thread has a
recorder. The nightly census installs that recorder, while a live request does
not. A typical Scientist setup instead connects this switch to a sampling rule.

### When Scientist alone is enough

Use Scientist alone when the path has enough live traffic to collect evidence
quickly. Live traffic gives a better input distribution than a census in this
case. Scientist also fits inputs from request parameters or a session. A census
can construct inputs from table rows, so it cannot evaluate those request-only
inputs. For one or two experiments, the census job, middleware, thresholds,
judge, and CI wiring can cost more than they save.

Greenroom becomes useful when agents create experiments faster than people can
review them. It addresses a review queue, not one experiment.

## What is here

| Directory | What it holds |
|---|---|
| `gems/greenroom` | the gem a Rails application loads: the experiment methods, the recorder, the census core, the boot assertion, and the `greenroom` command |
| `gems/rubocop-greenroom` | the cops that read one file and reject a shape an agent should not write |
| `skills` | the skills that teach the machinery |
| `docs` | the architecture and decision records |

## Status

Early. The gem is under construction, and the parts above arrive in order.

## License

MIT. See [LICENSE.txt](LICENSE.txt).
