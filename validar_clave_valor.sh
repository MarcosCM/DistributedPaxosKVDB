./compilar_clave_valor.sh
erl -connect_all false -noshell -name maestro@127.0.0.1 -rsh \
    -pa ./Paxos ./ServicioClaveValor ssh -setcookie 'palabrasecreta' \
    -eval "eunit:test(servicio_clave_valor_tests, [verbose])."  -run init stop

epmd -kill

#"eunit:test({timeout, 15, paxos})."
