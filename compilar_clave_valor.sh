cd ServicioClaveValor
erlc +debug_info servicio_clave_valor_tests.erl cliente.erl servidor.erl comun.erl
cd ../Paxos
erlc +debug_info paxos_tests.erl paxos.erl datos_paxos.erl aceptador.erl proponente.erl helper.erl
cd ..
