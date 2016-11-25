%% ----------------------------------------------------------------------------
%% Modulo: aceptador
%%
%% Descripcion : Funciones para el hilo del aceptador
%%
%% Autor : Marcos Canales Mayo
%%
%% ----------------------------------------------------------------------------

-module(aceptador).

-export([aceptador_start/2, aceptador_wait_msg/5]).

%% Iniciar aceptador
aceptador_start(NodoPaxos, NuInstancia) ->
	register(list_to_atom("aceptador" ++ integer_to_list(NuInstancia)), self()),
	aceptador_wait_msg(NodoPaxos, NuInstancia, {null, self()}, {null, self()}, null).

%% Aceptador escuchando
%% N = {integer(), pid()}
aceptador_wait_msg(NodoPaxos, NuInstancia, N_p, N_a, V_a) ->
	receive
		% Recibo un prepara
		{Pid, NuInstancia, prepara, N_recibido} ->
			aceptador_msg_prepara(NodoPaxos, NuInstancia, Pid, N_recibido, N_p, N_a, V_a);
		% Recibo un acepta
		{Pid, NuInstancia, acepta, N_recibido, V_recibido} ->
			aceptador_msg_acepta(NodoPaxos, NuInstancia, Pid, N_recibido, V_recibido, N_p, N_a, V_a);
		% Ya hay consenso en un valor
		{Pid, NuInstancia, decidido, Valor} ->
			{paxos, list_to_atom(lists:concat(["", NodoPaxos]))} ! {Pid, set_instancia, NuInstancia, Valor};
		true ->
			io:format("Aceptador ~p err~n", [NodoPaxos]),
			%%%%%%%%%
			% TO DO %
			%%%%%%%%%
			err
	end.

% Si instancia esta decidida
instancia_decidida(Pid, NuInstancia, N_recibido, Valor) ->
	{N_num, N_pid} = N_recibido,
	% Enviamos prepara_ok con el valor de la instancia y un N mayor
	Pid ! {self(), NuInstancia, prepara_ok, N_recibido, {N_num + 1, N_pid}, Valor}.

% Si instancia no esta decidida
instancia_no_decidida(NodoPaxos, Pid, NuInstancia, N_recibido, N_p, N_a, V_a) ->
	% Comparamos N con N_p
	Comparison = paxos:compare_n(N_p, N_recibido),
	if
		% Si N > N_p
		Comparison == higher ->
			io:format("Aceptador ~p enviando prepara_ok a ~p, instancia: ~p~n", [NodoPaxos, Pid, NuInstancia]),
			% Envio prepara_ok y actualizo mi N_p
			Pid ! {self(), NuInstancia, prepara_ok, N_recibido, N_a, V_a},
			aceptador_wait_msg(NodoPaxos, NuInstancia, N_recibido, N_a, V_a);
		% Sino
		true ->
			io:format("Aceptador ~p enviando prepara_reject a ~p, instancia: ~p~n", [NodoPaxos, Pid, NuInstancia]),
			% Envio prepara_reject ya que su N es menor
			Pid ! {self(), NuInstancia, prepara_reject, N_p},
			aceptador_wait_msg(NodoPaxos, NuInstancia, N_p, N_a, V_a)
	end.

%% Gestion del mensaje prepara en el aceptador
%% N = {integer(), pid()}
aceptador_msg_prepara(NodoPaxos, NuInstancia, Pid, N_recibido, N_p, N_a, V_a) ->
	io:format("Nodo ~p recibe prepara de instancia ~p~n", [NodoPaxos, NuInstancia]),
	% Comprobamos que el valor de la instancia no se encuentre decidido
	PaxosData = paxos:get_paxos_data(NodoPaxos),
	Instancias = datos_paxos:get_instancias(PaxosData),
	Instancia = dict:find(NuInstancia, Instancias),
	case Instancia of
		% Si la instancia esta decidida
		{ok, {true, Valor}} ->
			instancia_decidida(Pid, NuInstancia, N_recibido, Valor);
		% Sino
		_ ->
			instancia_no_decidida(NodoPaxos, Pid, NuInstancia, N_recibido, N_p, N_a, V_a)
	end.

%% Gestion del mensaje acepta en el aceptador
%% N = {integer(), pid()}
aceptador_msg_acepta(NodoPaxos, NuInstancia, Pid, N_recibido, V_recibido, N_p, N_a, V_a) ->
	io:format("Nodo ~p recibe acepta de instancia ~p~n", [NodoPaxos, NuInstancia]),
	% Comparamos N con N_p
	Comparison = paxos:compare_n(N_p, N_recibido),
	if
		% Si N >= N_p
		(Comparison == higher) or (Comparison == same) ->
			io:format("Aceptador ~p enviando acepta_ok a ~p, instancia: ~p~n", [NodoPaxos, Pid, NuInstancia]),
			Pid ! {self(), NuInstancia, acepta_ok, N_recibido},
			aceptador_wait_msg(NodoPaxos, NuInstancia, N_recibido, N_recibido, V_recibido);
		% Sino
		true ->
			io:format("Aceptador ~p enviando acepta_reject a ~p, instancia: ~p~n", [NodoPaxos, Pid, NuInstancia]),
			Pid ! {self(), NuInstancia, acepta_reject, N_p},
			aceptador_wait_msg(NodoPaxos, NuInstancia, N_p, N_a, V_a)
	end.
