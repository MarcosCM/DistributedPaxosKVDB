%% ----------------------------------------------------------------------------
%% Modulo: paxos
%%
%% Descripcion : Modulo principal del algoritmo Paxos
%%
%% Esqueleto por : Unai Arronategui
%% Autor : Marcos Canales Mayo
%%
%% ----------------------------------------------------------------------------


-module(paxos).

-export([start/2, start_instancia/3, estado/2, hecho/2, max/1, min/1]).

-export([comm_no_fiable/1, limitar_acceso/2, stop/1, vaciar_buzon/0]).
-export([n_mensajes/1]).
-export([ponte_sordo/1, escucha/1]).

-export([init/2]).

-export([compare_n/2]).
-export([get_paxos_data/2, get_paxos_data/1]).

-define(TIMEOUT, 300).


-define(PRINT(Texto,Datos), io:format(Texto,Datos)).
%-define(PRINT(Texto,Datos), ok)).

-define(ENVIO(Mensj, Dest),
		io:format("~p -> ~p -> ~p~n",[node(), Mensj, Dest]), Dest ! Mensj).
%-define(ENVIO(Mensj, Dest), Dest ! Mensj).

-define(ESPERO(Dato), Dato -> io:format("LLega ~p-> ~p~n",[Dato,node()]), ).
%-define(ESPERO(Dato), Dato -> ).


%% El que invoca a las funciones exportables es el nodo erlang maestro
%%  que es creado en otro programa...para arrancar los nodos replica (con paxos)

%% - Resto de nodos se arranca con slave:start(Host, Name, Args)
%% - Entradas/Salidas de todos los nodos son redirigidos por Erlang a este nodo
%%	   (es el funcionamiento especificado por modulo slave)
%% - Todos los nodos deben tener el mismo Sist de Fich. (NFS en distribuido ?)
 
%% - Args contiene string con parametros para comando shell "erl"
%% - Para la ejecucion en linea de comandos shell de la VM Erlang, 
%%   definir ssh en parametro -rsh y habilitar authorized_keys en nodos remotos


%%%%%%%%%%%% FUNCIONES EXPORTABLES  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


%%-----------------------------------------------------------------------------
%% Crear y poner en marcha un servidor Paxos
%% Los nombres Erlang completos de todos los servidores estan en Servidores
%% Y el nombre de maquina y nombre nodo Erlang de este servidor estan en 
%% Host y NombreNodo
%% Devuelve :  ok.
-spec start( list(node()), atom() ) -> ok.
start(Servidores, Nodo) ->
	process_flag(trap_exit, true),
	spawn_link(Nodo, ?MODULE, init, [Servidores, Nodo]).

%%-----------------------------------------------------------------------------
init(Servidores, Yo) ->
	register(paxos, self()),
	PaxosData = datos_paxos:new_paxos_data(Servidores, Yo),
	bucle_recepcion(Servidores, Yo, PaxosData).

%%-----------------------------------------------------------------------------
%% peticion de inicio de proceso de acuerdo para una instancia NuInstancia
%% Con valor propuesto Valor.
%% al servidor Paxos : NodoPaxos
%% Devuelve de inmediato:  ok. 
-spec start_instancia( node(), non_neg_integer(), string() ) -> ok.
start_instancia(NodoPaxos, NuInstancia, Valor) ->
	MinInstancia = min(NodoPaxos),
	if
		MinInstancia == timeout ->
			timeout;
		NuInstancia < MinInstancia ->
			ya_existe_proponente;
		true ->
			{paxos, list_to_atom(lists:concat(["", NodoPaxos]))} ! {self(), set_instancia, NuInstancia, {false, null}},
			N = erlang:monotonic_time(),
			spawn(list_to_atom(lists:concat(["", NodoPaxos])), aceptador, aceptador_start, [NodoPaxos, NuInstancia]),
			spawn(list_to_atom(lists:concat(["", NodoPaxos])), proponente, proponente_start, [NodoPaxos, NuInstancia, N, Valor]),
			ok
	end.

%%%%%%%%%%%%%%%%%  FUNCIONES LOCALES  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% Si la nueva N es mayor que la actual N devuelve higher
%% Si la nueva N es igual que la actual N devuelve same
%% Si la nueva N es menor que la actual N devuelve lower
compare_n({N, Id}, {NewN, NewId}) ->
	if
		(N == null) and (NewN == null) ->
			same;
		N == null ->
			higher;
		NewN == null ->
			lower;
		(NewN > N) or ((NewN == N) and (NewId > Id)) ->
			higher;
		(NewN == N) and (Id == NewId) ->
			same;
		true ->
			lower
	end.

% Obtener estructura de datos Paxos con tiempo de timeout
get_paxos_data(NodoPaxos, TimeOut) ->
	{paxos, list_to_atom(lists:concat(["", NodoPaxos]))} ! {self(), get_paxos_data},
	comun:get_msg(paxos_data, TimeOut).

% Obtener estructura de datos Paxos sin tiempo de timeout
get_paxos_data(NodoPaxos) ->
	{paxos, list_to_atom(lists:concat(["", NodoPaxos]))} ! {self(), get_paxos_data},
	comun:get_msg(paxos_data).
	
%%-----------------------------------------------------------------------------
bucle_recepcion(Servidores, Yo, PaxosData) ->
	receive
		no_fiable ->
			NewPaxosData = poner_no_fiable(PaxosData),
			bucle_recepcion(Servidores, Yo, NewPaxosData);

		fiable ->
			NewPaxosData = poner_fiable(PaxosData),
			bucle_recepcion(Servidores, Yo, NewPaxosData);

		{es_fiable, Pid} -> 
			Pid ! es_fiable(PaxosData),
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
		{'EXIT', _Pid, _DatoDevuelto} -> 
			%%%%%%%%%
			% TO DO %
			%%%%%%%%%
			bucle_recepcion(Servidores, Yo, PaxosData);



		% Obtener estructura de datos
		{Pid, get_paxos_data} ->
			Pid ! {paxos_data, PaxosData},
			bucle_recepcion(Servidores, Yo, PaxosData);

		% Actualizar un registro
		{_Pid, set_registro, NuInstancia, Valor} ->
			NewPaxosData = datos_paxos:set_registro(PaxosData, NuInstancia, Valor),
			bucle_recepcion(Servidores, Yo, NewPaxosData);

		% Actualizar una instancia
		{_Pid, set_instancia, NuInstancia, Valor} ->
			NewPaxosData = datos_paxos:set_instancia(PaxosData, NuInstancia, Valor),
			bucle_recepcion(Servidores, Yo, NewPaxosData);

		% Consenso en un valor del registro: actualizar y propagar al resto de nodos
		{_Pid, instancia_decidida, NuInstancia, Valor} ->
			% No es necesario actualizar aqui, ya lo hace el aceptador cuando le llega el "decidido"
			% NewPaxosData = datos_paxos:set_instancia(PaxosData, NuInstancia, Valor),
			lists:foreach(fun(Sv) ->
				{paxos, list_to_atom(lists:concat(["", Sv]))} ! {self(), NuInstancia, decidido, Valor}
			end, Servidores),
			bucle_recepcion(Servidores, Yo, PaxosData);

		% Actualiza el valor de hecho
		{_Pid, set_hecho, Servidor, NuInstancia} ->
			NewPaxosData = datos_paxos:set_hecho(PaxosData, Servidor, NuInstancia),
			bucle_recepcion(Servidores, Yo, NewPaxosData);

		% Obtener hecho
		{Pid, get_hecho} ->
			NuInstancia = datos_paxos:get_hecho(PaxosData),
			Pid ! {hecho, NuInstancia},
			bucle_recepcion(Servidores, Yo, PaxosData);

		% Actualizar el valor de max
		{_Pid, set_max, Max} ->
			NewPaxosData = datos_paxos:set_max(PaxosData, Max),
			bucle_recepcion(Servidores, Yo, NewPaxosData);

		{Pid, get_max} ->
			Max = datos_paxos:get_max(PaxosData),
			Pid ! {max, Max},
			bucle_recepcion(Servidores, Yo, PaxosData);

		% Mensajes para proponente y aceptador del servidor local
		Mensajes_prop_y_acept ->
			simula_fallo_mensj_prop_y_acep(Mensajes_prop_y_acept, Servidores, Yo, PaxosData),
			bucle_recepcion(Servidores, Yo, PaxosData)
	end.
	
%%-----------------------------------------------------------------------------
simula_fallo_mensj_prop_y_acep(Mensaje, Servidores, Yo, PaxosData) ->
	Es_fiable = es_fiable(PaxosData),
	Aleatorio = rand:uniform(1000),
	  %si no fiable, eliminar mensaje con cierta aleatoriedad
	if  ((not Es_fiable) and (Aleatorio < 200)) -> 
				bucle_recepcion(Servidores, Yo, PaxosData);
				  % Y si lo es tratar el mensaje recibido correctamente
		true -> gestion_mnsj_prop_y_acep(Mensaje, Servidores, Yo, PaxosData)
	end.

%% Comprueba si existe aceptador para la instancia
%% Si no existe lo crea
%% Devuelve el Pid del aceptador para la instancia
check_aceptador_alive(NodoPaxos, NuInstancia) ->
	Name = list_to_atom("aceptador" ++ integer_to_list(NuInstancia)),
	AceptadorPid = whereis(Name),
	if
		undefined == AceptadorPid ->
			spawn(NodoPaxos, aceptador, aceptador_start, [NodoPaxos, NuInstancia]);
		true ->
			AceptadorPid
	end.

%%-----------------------------------------------------------------------------
% implementar tratamiento de mensajes recibidos en Paxos
% Tanto por proponentes como aceptadores
gestion_mnsj_prop_y_acep(Mensaje, _Servidores, Yo, _PaxosData) ->
	case Mensaje of
		% Llega prepara a aceptador
		{_Pid, NuInstancia, prepara, _N} ->
			{paxos, Yo} ! {self(), set_max, NuInstancia},
			Pid = check_aceptador_alive(Yo, NuInstancia),
			Pid ! Mensaje;
		% Llega prepara_ok a proponente
		{_Pid, NuInstancia, prepara_ok, _N, _N_a, _V_a} ->
			{paxos, Yo} ! {self(), set_max, NuInstancia},
			{list_to_atom("proponente" ++ integer_to_list(NuInstancia)), Yo} ! Mensaje;
		% Llega prepara_reject a proponente
		{_Pid, NuInstancia, prepara_reject, _N} ->
			{paxos, Yo} ! {self(), set_max, NuInstancia},
			{list_to_atom("proponente" ++ integer_to_list(NuInstancia)), Yo} ! Mensaje;
		% Llega acepta a aceptador
		{_Pid, NuInstancia, acepta, _N, _V} ->
			{paxos, Yo} ! {self(), set_max, NuInstancia},
			Pid = check_aceptador_alive(Yo, NuInstancia),
			Pid ! Mensaje;
		% Llega acepta_ok a proponente
		{_Pid, NuInstancia, acepta_ok, _N} ->
			{paxos, Yo} ! {self(), set_max, NuInstancia},
			{list_to_atom("proponente" ++ integer_to_list(NuInstancia)), Yo} ! Mensaje;
		% Llega acepta_reject a proponente
		{_Pid, NuInstancia, acepta_reject, _N} ->
			{paxos, Yo} ! {self(), set_max, NuInstancia},
			{list_to_atom("proponente" ++ integer_to_list(NuInstancia)), Yo} ! Mensaje;
		% Llega decidido a aceptador
		{_Pid, NuInstancia, decidido, _V} ->
			{paxos, Yo} ! {self(), set_max, NuInstancia},
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
	%io:format("~p : Esperando a recibir escucha~n",[node()]),
	receive
		escucha ->
			%io:format("~p : Salgo de la sordera !!~n",[node()]),
			bucle_recepcion(Servidores, Yo, PaxosData);
		_Resto -> espero_escucha(Servidores, Yo, PaxosData)
	end.

%% Obtiene la estructura de paxos nueva con fiabilidad = no_fiable
poner_no_fiable(PaxosData) ->
	datos_paxos:set_fiabilidad(PaxosData, no_fiable).

%% Obtiene la estructura de paxos nueva con fiabilidad = fiable
poner_fiable(PaxosData) ->
	datos_paxos:set_fiabilidad(PaxosData, fiable).

%% Obtiene el atributo fiabilidad de la estructura de datos paxos
es_fiable(PaxosData) ->
	datos_paxos:get_fiabilidad(PaxosData).

%%-----------------------------------------------------------------------------
%% La aplicacion quiere saber si este servidor opina que
%% la instancia NuInstancia ya se ha decidido.
%% Solo debe mirar el servidor NodoPaxos sin contactar con ningun otro
%% Devuelve : {Decidido :: bool, Valor}
-spec estado( node(), non_neg_integer() ) -> { boolean() , string() }.
estado(NodoPaxos, NuInstancia) ->
	MinInstancia = min(NodoPaxos),
	if
		MinInstancia == timeout ->
			{false, null};
		NuInstancia < MinInstancia ->
			{false, null};
		true ->
			PaxosData = get_paxos_data(NodoPaxos, ?TIMEOUT),
			if
				PaxosData == timeout ->
					{false, null};
				true ->
					datos_paxos:get_registro(PaxosData, NuInstancia)
			end
	end.

%%-----------------------------------------------------------------------------
%% La aplicacion en el servidor NodoPaxos ya ha terminado
%% con todas las instancias <= NuInstancia
%% Mirar comentarios de min() para mas explicaciones
%% Devuelve :  ok.
-spec hecho( node(), non_neg_integer() ) -> ok.
hecho(NodoPaxos, NuInstancia) ->
	PaxosData = get_paxos_data(NodoPaxos),
	Servidores = datos_paxos:get_servidores(PaxosData),
	lists:foreach(fun(Sv) ->
		{paxos, list_to_atom(lists:concat(["", Sv]))} ! {self(), set_hecho, NodoPaxos, NuInstancia}
	end, Servidores).

%%-----------------------------------------------------------------------------
%% Aplicacion quiere saber el maximo numero de instancia que ha visto
%% este servidor NodoPaxos
% Devuelve : NuInstancia
-spec max( node() ) -> non_neg_integer().
max(NodoPaxos) ->
	PaxosData = get_paxos_data(NodoPaxos),
	datos_paxos:get_max(PaxosData).

%%-----------------------------------------------------------------------------
% Minima instancia vigente de entre todos los nodos Paxos
% Se calcula en funcion aceptador:modificar_state_inst_y_hechos
%Devuelve : NuInstancia = hecho + 1
-spec min( node() ) -> non_neg_integer().
min(NodoPaxos) ->
	PaxosData = get_paxos_data(NodoPaxos, ?TIMEOUT),
	if
		PaxosData == timeout ->
			timeout;
		true ->
			datos_paxos:get_min_hecho(PaxosData) + 1
	end.

%%-----------------------------------------------------------------------------
% Cambiar comportamiento de comunicacion del Nodo Erlang a NO FIABLE
-spec comm_no_fiable( node() ) -> no_fiable.
comm_no_fiable(Nodo) ->
	{paxos, list_to_atom(lists:concat(["", Nodo]))} ! no_fiable.
	
	
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
	slave:stop(list_to_atom(NodoPaxos)),
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
		{paxos, list_to_atom(NodoPaxos)} ! {n_mensajes, self()},
		receive Respuesta -> Respuesta end.
