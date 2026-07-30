def paint($code):
  if (env.SYMBOLIC_COLOR // "1") == "0" then
    .
  else
    "\u001b[\($code)m\(.)\u001b[0m"
  end;

def render:
  .result as $result
  | (if $result.status == "pass" then
       "PASS" | paint("1;32")
     elif $result.status == "fail_counterexample" then
       "FAIL" | paint("1;31")
     else
       "INCOMPLETE" | paint("1;33")
     end) as $label
  | "\($label) \("\(.contract)::\(.test)" | paint("1;36"))"
    + ("\n  bounds: invariant_depth=\($result.bounds.invariant_depth), max_paths=\($result.bounds.max_paths), timeout=\($result.bounds.timeout_seconds)s" | paint("2"))
    + ("\n  solver: \($result.solver.name), paths=\($result.solver.stats.paths), queries=\($result.solver.stats.solver_queries), time=\($result.solver.stats.solver_time_ms)ms" | paint("2"))
    + (if $result.incomplete != null then
         "\n  reason: \($result.incomplete.kind): \($result.incomplete.reason)" | paint("33")
       else
         ""
       end)
    + (if $result.replay.required then
         "\n  replay: \($result.replay.status)" | paint("35")
       else
         ""
       end)
    + (if $result.counterexample != null then
         "\n  counterexample: \($result.counterexample | tojson)" | paint("31")
       else
         ""
       end);

[
  to_entries[] as $suite
  | $suite.value.test_results
  | to_entries[]
  | select(.value.symbolic != null)
  | {
      contract: $suite.key,
      test: .key,
      result: .value.symbolic
    }
] as $results
| if ($results | length) == 0 then
    "No symbolic results found\n" | halt_error(2)
  else
    ($results[] | render),
    (if any($results[]; .result.status != "pass") then
       "One or more symbolic tests did not pass\n" | halt_error(1)
     else
       empty
     end)
  end
