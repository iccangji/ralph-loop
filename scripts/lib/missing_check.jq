def check_missing_deps:
  . as $tasks
  | ($tasks | map(.id)) as $all_ids
  | [ $tasks[] | (.depends_on // [])[] | select(. as $d | ($all_ids | index($d)) == null) ]
  | if length > 0 then "MISSING" else "OK" end;

check_missing_deps