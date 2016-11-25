erl -noshell -name maestro@127.0.0.1 -rsh ssh -setcookie 'palabrasecreta' -eval "eunit:test(paxos)."  -run init stop
