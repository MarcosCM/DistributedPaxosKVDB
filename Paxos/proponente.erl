%% ----------------------------------------------------------------------------
%% Modulo: proponente
%%
%% Descripcion : Funciones para el hilo del proponente
%%
%% Autor : Marcos Canales Mayo
%%
%% ----------------------------------------------------------------------------

-module(proponente).

-export([proponente_start/4, proponente_wait_prepara/7, proponente_wait_acepta/5]).

%% Iniciar proponente
%% N = integer()
proponente_start(NodoPaxos, NuInstancia, N, Valor) ->
	register(list_to_atom("proponente" ++ integer_to_list(NuInstancia)), self()),
	%io:format("Proponente ~p start Instancia ~p N ~p Valor ~p~n", [NodoPaxos, NuInstancia, N, Valor]),
	% Lista de nodos
	PaxosData = paxos:get_paxos_data(NodoPaxos),
	Servidores = datos_paxos:get_servidores(PaxosData),
	NeededVotes = trunc((length(Servidores) / 2) + 1),
	{IsMajority, _ChosenN, ChosenV} = proponente_fase_preparas(NodoPaxos, Servidores, NuInstancia, NeededVotes, N, Valor),
	%io:format("ChosenV: ~p~n", [ChosenV]),
	if
		% Si no recibe mayoria de prepara_ok entonces nueva proposicion
		IsMajority == false ->
			NewN = erlang:monotonic_time(),
			proponente_start(NodoPaxos, NuInstancia, NewN, Valor);
		% Si recibe mayoria de prepara_ok entonces pedimos mayoria de aceptadores
		true ->
			proponente_fase_aceptas(NodoPaxos, Servidores, NuInstancia, NeededVotes, N, ChosenV)
	end.

% Fase de solicitar y recibir preparas
proponente_fase_preparas(NodoPaxos, Servidores, NuInstancia, NeededVotes, N, Valor) ->
	% Envia prepara(n)
	lists:foreach(fun(Sv) ->
		%io:format("Enviando prepara a ~p: {~p, ~p}~n", [Sv, NuInstancia, N]),
		{paxos, list_to_atom(lists:concat(["", Sv]))} ! {self(), NuInstancia, prepara, {N, self()}}
	end, Servidores),
	% Espera a prepara_ok(n, n_a, v_a)
	proponente_wait_prepara(NodoPaxos, NuInstancia, NeededVotes,
							{N, self()}, Valor,
							{N, self()}, Valor).

% Fase de solicitar y recibir aceptas
proponente_fase_aceptas(NodoPaxos, Servidores, NuInstancia, NeededVotes, N, ChosenV) ->
	% Nueva instancia de Paxos
	{paxos, list_to_atom(lists:concat(["", NodoPaxos]))} ! {self(), set_instancia, NuInstancia, {false, null}},
	% Solicitamos mayoria de aceptadores
	lists:foreach(fun(Sv) ->
		%io:format("Proponente ~p enviando acepta a ~p~n", [NodoPaxos, Sv]),
		{paxos, list_to_atom(lists:concat(["", Sv]))} ! {self(), NuInstancia, acepta, {N, self()}, ChosenV}
	end, Servidores),
	% Esperamos a la mayoria de aceptadores
	Decidido = proponente_wait_acepta(NodoPaxos, NuInstancia, NeededVotes, {N, self()}, ChosenV),
	if
		% No se ha llegado a consenso
		Decidido == false ->
			not_decidido;
		% Mayoria de aceptadores han llegado a consenso
		true ->
			decidido
	end.

%% Mientras no tenga los prepara_ok necesarios
%% N = {integer(), pid()}
proponente_wait_prepara(NodoPaxos, NuInstancia, NeededVotes, N, V, HighestN, HighestV) when NeededVotes > 0 ->
	receive
		{_Pid, NuInstancia, prepara_ok, N, N_a, V_a} ->
			% Recibo un prepara_ok
			Comparison = paxos:compare_n(HighestN, N_a),
			if
				Comparison == lower ->
					proponente_wait_prepara(NodoPaxos, NuInstancia, NeededVotes - 1,
								N, V,
								HighestN, HighestV);
				true ->
					proponente_wait_prepara(NodoPaxos, NuInstancia, NeededVotes - 1,
								N, V,
								N_a, V_a)
			end;
		true ->
			%io:format("proponente_wait_prepara(): err~n", []),
			err
	end;

%% Cuando ya tengo los prepara_ok necesarios
%% N = {integer(), pid()}
proponente_wait_prepara(_NodoPaxos, _NuInstancia, _NeededVotes, N, V, HighestN, HighestV) ->
	Comparison = paxos:compare_n(N, HighestN),
	if
		% Mi N es el mayor
		Comparison == lower->
			ChosenN = N,
			ChosenV = V;
		% Hay un N mayor que el mio
		true ->
			ChosenN = HighestN,
			ChosenV = HighestV
	end,
	%io:format("Proponente pasa fase de preparacion instancia ~p~n", [NuInstancia]),
	{true, ChosenN, ChosenV}.

%% Mientras no tenga los acepta_ok necesarios
%% N = {integer(), pid()}
proponente_wait_acepta(NodoPaxos, NuInstancia, NeededVotes, N, V) when NeededVotes > 0 ->
	receive
		% Recibo un acepta_ok
		{_Pid, NuInstancia, acepta_ok, N} ->
			%io:format("Proponente ~p recibe acepta_ok instancia: ~p~n", [NodoPaxos, NuInstancia]),
			proponente_wait_acepta(NodoPaxos, NuInstancia, NeededVotes - 1, N, V);
		true ->
			err
	end;

%% Cuando ya tengo los acepta_ok necesarios
%% N = {integer(), pid()}
proponente_wait_acepta(NodoPaxos, NuInstancia, _NeededVotes, _N, V) ->
	%io:format("Proponente ~p ya tiene los acepta_ok necesarios~n", [NodoPaxos]),
	{paxos, list_to_atom(lists:concat(["", NodoPaxos]))} ! {self(), instancia_decidida, NuInstancia, {true, V}}.
