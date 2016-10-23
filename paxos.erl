%% ----------------------------------------------------------------------------
%% paxos : Modulo principal Paxos
%%
%% 
%% 
%% 
%% 
%% ----------------------------------------------------------------------------


-module(paxos).

-export([start/3, start_instancia/3, estado/2, hecho/2, max/1, min/1]).

-export([comm_no_fiable/1, limitar_acceso/2, stop/1, vaciar_buzon/0]).
-export([n_mensajes/1]).
-export([ponte_sordo/1, escucha/1]).

-export([init/2]).

-export([proponente_start/4, proponente_wait_prepara/7, proponente_wait_acepta/5]).
-export([aceptador_start/2, aceptador_wait_msg/5]).
-export([compare_n/2]).

-define(TIMEOUT, 3).


-define(PRINT(Texto,Datos), io:format(Texto,Datos)).
%-define(PRINT(Texto,Datos), ok)).

-define(ENVIO(Mensj, Dest),
		io:format("~p -> ~p -> ~p~n",[node(), Mensj, Dest]), Dest ! Mensj).
%-define(ENVIO(Mensj, Dest), Dest ! Mensj).

-define(ESPERO(Dato), Dato -> io:format("LLega ~p-> ~p~n",[Dato,node()]), ).
%-define(ESPERO(Dato), Dato -> ).


%% El que invoca a las funciones exportables es el nodo erlang maestro
%%  que es cr4eado en otro programa...para arrancar los nodos réplica (con paxos)

%% - Resto de nodos se arranca con slave:start(Host, Name, Args)
%% - Entradas/Salidas de todos los nodos son redirigidos por Erlang a este nodo
%%	   (es el funcionamiento especificado por modulo slave)
%% - Todos los  nodos deben tener el mismo Sist de Fich. (NFS en distribuido ?)
 
%% - Args contiene string con parametros para comando shell "erl"
%% - Para la ejecución en línea de comandos shell de la VM Erlang, 
%%   definir ssh en parámetro -rsh y habilitar authorized_keys en nodos remotos


%%%%%%%%%%%% FUNCIONES EXPORTABLES  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


%%-----------------------------------------------------------------------------
%% Crear y poner en marcha un servidor Paxos
%% Los nombres Erlang completos de todos los servidores están en Servidores
%% Y el nombre de máquina y nombre nodo Erlang de este servidor están en 
%% Host y NombreNodo
%% Devuelve :  ok.
-spec start( list(node()), atom(), atom() ) -> ok.
start(Servidores, Host, NombreNodo) ->
	Args = "-setcookie palabrasecreta", % args para comando remoto erl
		% arranca servidor en nodo remoto
	{ok, Nodo} = slave:start(Host, NombreNodo, Args),
	io:format("Nodo esclavo en marcha~n",[]),
	process_flag(trap_exit, true),
	spawn_link(Nodo, ?MODULE, init, [Servidores, Nodo]).

%%-----------------------------------------------------------------------------
init(Servidores, Yo) ->
	register(paxos, self()),
	%%%%% VUESTRO CODIGO DE INICIALIZACION AQUI

	PaxosData = datos_paxos:new_paxos_data(Servidores, Yo),
	bucle_recepcion(Servidores, Yo, PaxosData).

%%-----------------------------------------------------------------------------
%% petición de inicio de proceso de acuerdo para una instancia NuInstancia
%% Con valor propuesto Valor.
%% al servidor Paxos : NodoPaxos
%% Devuelve de inmediato:  ok. 
-spec start_instancia( node(), non_neg_integer(), string() ) -> ok.
start_instancia(NodoPaxos, NuInstancia, Valor) ->
	%%%%% VUESTRO CODIGO AQUI
	MinInstancia = min(NodoPaxos),
	if
		NuInstancia < MinInstancia ->
			ya_existe_proponente;
		true ->
			{paxos, NodoPaxos} ! {self(), set_instancia, NuInstancia, {false, null}},
			N = erlang:monotonic_time(),
			spawn(NodoPaxos, ?MODULE, aceptador_start, [NodoPaxos, NuInstancia]),
			spawn(NodoPaxos, ?MODULE, proponente_start, [NodoPaxos, NuInstancia, N, Valor]),
			ok
	end.

%%%%%%%%%%%%%%%%%  FUNCIONES LOCALES  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% Si la nueva N es mayor que la actual N devuelve higher
%% Si la nueva N es igual que la actual N devuelve same
%% Si la nueva N es menor que la actual N devuelve lower
compare_n({N, Id}, {NewN, NewId}) ->
	if
		(NewN > N) or ((NewN == N) and (NewId > Id)) ->
			higher;
		(NewN == N) and (Id == NewId) ->
			same;
		true ->
			lower
	end.

%% Reenviar mensajes almacenados en el buffer
resend_msg_buff([]) ->
	buff_empty;

resend_msg_buff([H|T]) ->
	self() ! H,
	resend_msg_buff(T).

%% Obtener la estructura de datos paxos de forma segura con un tiempo de timeout
get_paxos_data(NodoPaxos, PaxosDataType, MsgBuff, TimeOut) ->
	receive
		PaxosData when paxos == element(1, PaxosData) ->
			resend_msg_buff(MsgBuff),
			PaxosData;
		Msg ->
			get_paxos_data(NodoPaxos, PaxosDataType, MsgBuff ++ [Msg])
	after TimeOut ->
		timeout
	end.

get_paxos_data(NodoPaxos, TimeOut) ->
	PaxosDataType = datos_paxos:new_paxos_data([], self()),
	{paxos, NodoPaxos} ! {self(), get_paxos_data},
	get_paxos_data(NodoPaxos, PaxosDataType, [], TimeOut).

%% Obtener la estructura de datos paxos de forma segura sin tiempo de timeout
get_paxos_data(NodoPaxos, PaxosDataType, MsgBuff) ->
	receive
		PaxosData when paxos == element(1, PaxosData) ->
			resend_msg_buff(MsgBuff),
			PaxosData;
		Msg ->
			get_paxos_data(NodoPaxos, PaxosDataType, MsgBuff ++ [Msg])
	end.

%% Obtener lista de servidores
get_paxos_data(NodoPaxos) ->
	PaxosDataType = datos_paxos:new_paxos_data([], self()),
	{paxos, NodoPaxos} ! {self(), get_paxos_data},
	get_paxos_data(NodoPaxos, PaxosDataType, []).

proponente_start(NodoPaxos, NuInstancia, N, Valor) ->
	register(list_to_atom("proponente" ++ integer_to_list(NuInstancia)), self()),
	% Lista de nodos
	PaxosData = get_paxos_data(NodoPaxos),
	Servidores = datos_paxos:get_servidores(PaxosData),
	% Envia prepara(n)
	lists:foreach(fun(Sv) ->
		io:format("Enviando prepara a ~p~n", [Sv]),
		{paxos, Sv} ! {self(), NuInstancia, prepara, {N, self()}}
	end, Servidores),
	% Espera a prepara_ok(n, n_a, v_a)
	NeededVotes = trunc((length(Servidores) / 2) + 1),
	{IsMajority, ChosenN, ChosenV} = proponente_wait_prepara(NodoPaxos, NuInstancia, NeededVotes,
							{N, self()}, Valor,
							{N, self()}, Valor),
	if
		% Si no recibe mayoria de prepara_ok entonces nueva proposicion
		IsMajority == false ->
			NewN = erlang:monotonic_time(),
			proponente_start(NodoPaxos, NuInstancia, NewN, Valor);
		% Si recibe mayoria de prepara_ok entonces pedimos mayoria de aceptadores
		true ->
			% Nueva instancia de Paxos
			{paxos, NodoPaxos} ! {self(), set_instancia, NuInstancia, {false, null}},
			% Solicitamos mayoria de aceptadores
			lists:foreach(fun(Sv) ->
				io:format("Proponente ~p enviando acepta a ~p~n", [NodoPaxos, Sv]),
				{paxos, Sv} ! {self(), NuInstancia, acepta, {N, self()}, ChosenV}
			end, Servidores),
			% Esperamos a la mayoria de aceptadores
			Decidido = proponente_wait_acepta(NodoPaxos, NuInstancia, NeededVotes, {N, self()}, ChosenV),
			if
				% No se ha llegado a consenso
				Decidido == false ->
					%%%%%%%%%
					% TO DO %
					%%%%%%%%%
					not_decidido;
				% Mayoria de aceptadores han llegado a consenso
				true ->
					%%%%%%%%%
					% TO DO %
					%%%%%%%%%
					decidido
			end
	end.

% No tengo los prepara_ok necesarios
proponente_wait_prepara(NodoPaxos, NuInstancia, NeededVotes, N, V, HighestN, HighestV) when NeededVotes > 0 ->
	receive
		{_Pid, NuInstancia, prepara_ok, N, N_a, V_a} ->
			% Recibo un prepara_ok
			Comparison = compare_n(HighestN, N_a),
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
			io:format("proponente_wait_prepara(): err~n", []),
			%%%%%%%%%
			% TO DO %
			%%%%%%%%%
			err
	end;

% Ya tengo los prepara_ok necesarios
proponente_wait_prepara(_NodoPaxos, NuInstancia, _NeededVotes, N, V, HighestN, HighestV) ->
	Comparison = compare_n(N, HighestN),
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
	io:format("Proponente pasa fase de preparacion instancia ~p~n", [NuInstancia]),
	{true, ChosenN, ChosenV}.

% No tengo los acepta_ok necesarios
proponente_wait_acepta(NodoPaxos, NuInstancia, NeededVotes, N, V) when NeededVotes > 0 ->
	receive
		% Recibo un acepta_ok
		{_Pid, NuInstancia, acepta_ok, N} ->
			io:format("Proponente ~p recibe acepta_ok instancia: ~p~n", [NodoPaxos, NuInstancia]),
			proponente_wait_acepta(NodoPaxos, NuInstancia, NeededVotes - 1, N, V);
		true ->
			io:format("proponente_wait_acepta(): err~n", []),
			%%%%%%%%%
			% TO DO %
			%%%%%%%%%
			err
	end;

% Ya tengo los acepta_ok necesarios
proponente_wait_acepta(NodoPaxos, NuInstancia, NeededVotes, N, V) ->
	io:format("Proponente ~p ya tiene los acepta_ok necesarios~n", [NodoPaxos]),
	{paxos, NodoPaxos} ! {self(), instancia_decidida, NuInstancia, {true, V}}.

% Inicializar aceptador
aceptador_start(NodoPaxos, NuInstancia) ->
	register(list_to_atom("aceptador" ++ integer_to_list(NuInstancia)), self()),
	aceptador_wait_msg(NodoPaxos, NuInstancia, {-1, self()}, {-1, self()}, null).

aceptador_msg_prepara(NodoPaxos, NuInstancia, Pid, N_recibido, N_p, N_a, V_a) ->
	io:format("Nodo ~p recibe prepara de instancia ~p~n", [NodoPaxos, NuInstancia]),
	% Comprobamos que el valor de la instancia no se encuentre decidido
	PaxosData = get_paxos_data(NodoPaxos),
	io:format("get_paxos_data: ~p~n", [PaxosData]),
	Instancias = datos_paxos:get_instancias(PaxosData),
	Instancia = dict:find(NuInstancia, Instancias),
	case Instancia of
		% Si la instancia esta decidida
		{ok, {true, Valor}} ->
			{N_num, N_pid} = N_recibido,
			% Enviamos prepara_ok con el valor de la instancia y un N mayor
			Pid ! {self(), NuInstancia, prepara_ok, N_recibido, {N_num + 1, N_pid}, Valor};
		% Sino
		_ ->
			% Comparamos N con N_p
			Comparison = compare_n(N_p, N_recibido),
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
			end
	end.

aceptador_msg_acepta(NodoPaxos, NuInstancia, Pid, N_recibido, V_recibido, N_p, N_a, V_a) ->
	io:format("Nodo ~p recibe acepta de instancia ~p~n", [NodoPaxos, NuInstancia]),
	% Comparamos N con N_p
	Comparison = compare_n(N_p, N_recibido),
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

% Aceptador escuchando
% N_p = {integer(), pid()}
% N_a = {integer(), pid()}
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
			{paxos, NodoPaxos} ! {Pid, set_instancia, NuInstancia, Valor};
		true ->
			io:format("Aceptador ~p err~n", [NodoPaxos]),
			%%%%%%%%%
			% TO DO %
			%%%%%%%%%
			err
	end.
	
%%-----------------------------------------------------------------------------
bucle_recepcion(Servidores, Yo, PaxosData) ->
	receive
		no_fiable ->
			poner_no_fiable(),
			bucle_recepcion(Servidores, Yo, PaxosData);

		fiable ->
			poner_fiable(),
			bucle_recepcion(Servidores, Yo, PaxosData);

		{es_fiable, Pid} -> 
			Pid ! es_fiable(),
			bucle_recepcion(Servidores, Yo, PaxosData);

		{limitar_acceso, Nodos} ->
			%%  para que no de errores con conexiones no validas
			error_logger:tty(false), 
			net_kernel:allow(Nodos),
			bucle_recepcion(Servidores, Yo, PaxosData);

		{n_mensajes, Pid} ->
			Pid ! datos_paxos:get_num_mensajes(PaxosData),
			bucle_recepcion(Servidores, Yo, PaxosData);

		ponte_sordo -> espero_escucha(Servidores, Yo, PaxosData);
		
		%%Cuando proceso proponente acaba
		{'EXIT', _Pid, DatoDevuelto} -> 
			%%%%%%%%%
			% TO DO %
			%%%%%%%%%
			bucle_recepcion(Servidores, Yo, PaxosData);

		%%%%% VUESTRO CODIGO AQUI

		% Obtener estructura de datos
		{Pid, get_paxos_data} ->
			Pid ! PaxosData,
			bucle_recepcion(Servidores, Yo, PaxosData);
		{Pid, set_instancia, NuInstancia, Valor} ->
			NewPaxosData = datos_paxos:set_instancia(PaxosData, NuInstancia, Valor),
			bucle_recepcion(Servidores, Yo, NewPaxosData);
		% Consenso en un valor del registro: actualizar y propagar al resto de nodos
		{Pid, instancia_decidida, NuInstancia, Valor} ->
			NewPaxosData = datos_paxos:set_instancia(PaxosData, NuInstancia, Valor),
			lists:foreach(fun(Sv) ->
				{paxos, Sv} ! {self(), NuInstancia, decidido, Valor}
			end, Servidores),
			bucle_recepcion(Servidores, Yo, NewPaxosData);
		% Mensajes para proponente y aceptador del servidor local
		Mensajes_prop_y_acept ->
			simula_fallo_mensj_prop_y_acep(Mensajes_prop_y_acept, Servidores, Yo, PaxosData),
			bucle_recepcion(Servidores, Yo, PaxosData)
	end.
	
%%-----------------------------------------------------------------------------
simula_fallo_mensj_prop_y_acep(Mensaje, Servidores, Yo, PaxosData) ->
	Es_fiable = es_fiable(),
	Aleatorio = rand:uniform(1000),
	  %si no fiable, eliminar mensaje con cierta aleatoriedad
	if  ((not Es_fiable) and (Aleatorio < 200)) -> 
				bucle_recepcion(Servidores, Yo, PaxosData);
				  % Y si lo es tratar el mensaje recibido correctamente
		true -> gestion_mnsj_prop_y_acep(Mensaje, Servidores, Yo, PaxosData)
	end.

check_aceptador_alive(NodoPaxos, NuInstancia) ->
	Name = list_to_atom("aceptador" ++ integer_to_list(NuInstancia)),
	AceptadorPid = whereis(Name),
	if
		AceptadorPid == undefined ->
			spawn(NodoPaxos, ?MODULE, aceptador_start, [NodoPaxos, NuInstancia]);
		true ->
			AceptadorPid
	end.

%%-----------------------------------------------------------------------------
% implementar tratamiento de mensajes recibidos en Paxos
% Tanto por proponentes como aceptadores
gestion_mnsj_prop_y_acep(Mensaje, Servidores, Yo, PaxosData) ->
	%%%%% VUESTRO CODIGO AQUI

	case Mensaje of
		% Llega prepara a aceptador
		{_Pid, NuInstancia, prepara, _N} ->
			Pid = check_aceptador_alive(Yo, NuInstancia),
			Pid ! Mensaje;
		% Llega prepara_ok a proponente
		{_Pid, NuInstancia, prepara_ok, _N, _N_a, _V_a} ->
			{list_to_atom("proponente" ++ integer_to_list(NuInstancia)), Yo} ! Mensaje;
		% Llega prepara_reject a proponente
		{_Pid, NuInstancia, prepara_reject, _N} ->
			{list_to_atom("proponente" ++ integer_to_list(NuInstancia)), Yo} ! Mensaje;
		% Llega acepta a aceptador
		{_Pid, NuInstancia, acepta, _N, _V} ->
			Pid = check_aceptador_alive(Yo, NuInstancia),
			Pid ! Mensaje;
		% Llega acepta_ok a proponente
		{_Pid, NuInstancia, acepta_ok, _N} ->
			{list_to_atom("proponente" ++ integer_to_list(NuInstancia)), Yo} ! Mensaje;
		% Llega acepta_reject a proponente
		{_Pid, NuInstancia, acepta_reject, _N} ->
			{list_to_atom("proponente" ++ integer_to_list(NuInstancia)), Yo} ! Mensaje;
		% Llega decidido a aceptador
		{_Pid, NuInstancia, decidido, _V} ->
			Pid = check_aceptador_alive(Yo, NuInstancia),
			Pid ! Mensaje;
		_ ->
			%%%%%%%%%
			% TO DO %
			%%%%%%%%%
			err
	end.

%%-----------------------------------------------------------------------------
espero_escucha(Servidores, Yo, PaxosData) ->
	io:format("~p : Esperando a recibir escucha~n",[node()]),
	receive
		escucha ->
			io:format("~p : Salgo de la sordera !!~n",[node()]),
			bucle_recepcion(Servidores, Yo, PaxosData);
		_Resto -> espero_escucha(Servidores, Yo, PaxosData)
	end.

poner_no_fiable() ->
	%%%%%%%%%
	% TO DO %
	%%%%%%%%%
	err.

poner_fiable() ->
	%%%%%%%%%
	% TO DO %
	%%%%%%%%%
	err.

es_fiable() ->
	%%%%%%%%%
	% TO DO %
	%%%%%%%%%
	err.

%%-----------------------------------------------------------------------------
%% La aplicación quiere saber si este servidor opina que
%% la instancia NuInstancia ya se ha decidido.
%% Solo debe mirar el servidor NodoPaxos sin contactar con ningún otro
%% Devuelve : {Decidido :: bool, Valor}
-spec estado( node(), non_neg_integer() ) -> { boolean() , string() }.
estado(NodoPaxos, NuInstancia) ->
	MinInstancia = min(NodoPaxos),
	if
		NuInstancia < MinInstancia ->
			{false, null};
		true ->
			TimeOut = 300,
			PaxosData = get_paxos_data(NodoPaxos, TimeOut),
			if
				PaxosData == timeout ->
					io:format("Instancia ~p~n", [{false, null}]),
					{false, null};
				true ->
					Instancias = datos_paxos:get_instancias(PaxosData),
					Instancia = dict:find(NuInstancia, Instancias),
					if
						% Si la instancia no esta almacenada
						Instancia == error ->
							io:format("Instancia ~p~n", [{false, null}]),
							{false, null};
						% Si esta almacenada devolvemos su valor
						true ->
							{ok, ValorInstancia} = Instancia,
							io:format("Instancia ~p~n", [ValorInstancia]),
							ValorInstancia
					end
			end
	end.
	%%%%% VUESTRO CODIGO AQUI


%%-----------------------------------------------------------------------------
%% La aplicación en el servidor NodoPaxos ya ha terminado
%% con todas las instancias <= NuInstancia
%% Mirar comentarios de min() para más explicaciones
%% Devuelve :  ok.
-spec hecho( node(), non_neg_integer() ) -> ok.
hecho(NodoPaxos, NuInstancia) ->
	%%%%%%%%%
	% TO DO %
	%%%%%%%%%
	err.
	%%%%% VUESTRO CODIGO AQUI


%%-----------------------------------------------------------------------------
%% Aplicación quiere saber el máximo número de instancia que ha visto
%% este servidor NodoPaxos
% Devuelve : NuInstancia
-spec max( node() ) -> non_neg_integer().
max(NodoPaxos) ->
	%%%%%%%%%
	% TO DO %
	%%%%%%%%%
	err.
	%%%%% VUESTRO CODIGO AQUI

%%-----------------------------------------------------------------------------
% Minima instancia vigente de entre todos los nodos Paxos
% Se calcula en función aceptador:modificar_state_inst_y_hechos
%Devuelve : NuInstancia = hecho + 1
-spec min( node() ) -> non_neg_integer().
min(NodoPaxos) ->
	%%%%%%%%%
	% TO DO %
	%%%%%%%%%
	1.
	%%%%% VUESTRO CODIGO AQUI


%%-----------------------------------------------------------------------------
% Cambiar comportamiento de comunicación del Nodo Erlang a NO FIABLE
-spec comm_no_fiable( node() ) -> no_fiable.
comm_no_fiable(Nodo) ->
	{paxos, Nodo} ! no_fiable.
	
	
%%%%%%%%%%%%%%%%%%
%% Limitar acceso de un Nodo a solo otro conjunto de Nodos,
%% incluido este nodo de control
%% Para simular particiones de red
-spec limitar_acceso( node(), list(node()) ) -> ok.
limitar_acceso(Nodo, Nodos) ->
	{paxos, Nodo} ! {limitar_acceso, Nodos ++ [node()]}.
	
	
%%-----------------------------------------------------------------------------
%% Hacer que un servidor Paxos deje de escuchar cualquier mensaje salvo 'escucha'
-spec ponte_sordo( node() ) -> ponte_sordo.
ponte_sordo(NodoPaxos) ->
	{paxos, NodoPaxos} ! ponte_sordo.


%%-----------------------------------------------------------------------------
%% Hacer que el servidor Paxos vuelva a recibir todos los mensajes normales
-spec escucha( node() ) -> escucha.
escucha(NodoPaxos) ->
	{paxos, NodoPaxos} ! escucha.


%%-----------------------------------------------------------------------------
%% Parar nodo Erlang remoto
-spec stop( node() ) -> ok.
stop(NodoPaxos) ->
	slave:stop(NodoPaxos),
	vaciar_buzon().
	
%%-----------------------------------------------------------------------------
% Vaciar buzon de un proceso, tambien llamado en otros sitios flush()
-spec vaciar_buzon() -> ok.
vaciar_buzon() ->
	receive _ -> vaciar_buzon()
	after   0 -> ok
	end.


%%-----------------------------------------------------------------------------
%% Obtener numero de mensajes recibidos en un nodo
-spec n_mensajes( node() ) -> non_neg_integer().
n_mensajes(NodoPaxos) ->
		{paxos, NodoPaxos} ! {n_mensajes, self()},
		receive Respuesta -> Respuesta end.