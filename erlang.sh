erl -name maestro@127.0.0.1 -rsh ssh -pa ./Paxos ./ServicioClaveValor \
    -setcookie 'palabrasecreta'