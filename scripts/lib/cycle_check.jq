def has_cycle:
  . as $tasks
  | ($tasks | map(.id) | map({(.): 0}) | add) as $indeg
  | ($tasks | map({id, deps: (.depends_on // [])})) as $nodes
  | ($nodes
    | reduce .[] as $n ($indeg;
        reduce $n.deps[] as $d (.; .[$d] += 1)
      )
  ) as $indeg
  | ($indeg | to_entries | map(select(.value == 0) | .key)) as $queue
  | ($queue | length) as $qlen
  | if $qlen == 0 then "CYCLE" else "OK" end;

has_cycle