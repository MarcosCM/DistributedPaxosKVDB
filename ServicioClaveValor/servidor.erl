%% ----------------------------------------------------------------------------
%% Modulo: servidor
%%
%% Descripcion : Modulo principal del servicio de almacen distribuido clave/valor
%%
%% Esqueleto por : Unai Arronategui
%% Autor : Marcos Canales Mayo
%%
%% ----------------------------------------------------------------------------

-module(servidor).

-export([start/3, stop/1]).

-export([init/2]).

-define(TIMEOUT, 150).
-define(MAX_ESPERA_CONSENSO, 1).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Poner en marcha un nodo Paxos
%% Devuelve :  el nombre completo del nodo erlang.
%% La especificación del interfaz de la función es la siguiente :
%%                      (se puede utilizar también para "dialyzer")
-spec start( [ atom() ], atom(), atom() ) -> node().
start(Servidores, Host, NombreNodo) ->
    io:format("Arrancar un nodo servidor C/V~n",[]),

    % args para comando remoto erl
    Args = "-connect_all false -setcookie palabrasecreta" ++ 
            " -pa ./Paxos ./ServicioClaveValor",
    % arranca servidor en nodo remoto
    {ok, Nodo} = slave:start(Host, NombreNodo, Args),
    io:format("Nodo esclavo servidor C/V en marcha~n",[]),
    process_flag(trap_exit, true),
    spawn_link(Nodo, ?MODULE, init, [Servidores, Nodo]),
    paxos:start(Servidores, Nodo),
    Nodo.

%%-----------------------------------------------------------------------------
init(Servidores, Yo) ->
    register(servidor, self()),
    
    BaseDatos = dict:new(),
    bucle_recepcion(Servidores, Yo, BaseDatos, 0, []).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Parar nodo Erlang remoto
-spec stop( atom() ) -> ok.
stop(Nodo) ->
    slave:stop(Nodo),
    timer:sleep(10),
    comun:vaciar_buzon(),
    ok.

%%-----------------------------------------------------------------------------
% UpdatedUntil indica hasta que numero de instancia esta actualizado este servidor
bucle_recepcion(Servidores, Yo, BaseDatos, UpdatedUntil, ListaUUID) ->
    receive
    	% Comprobacion de si una UUID esta en mi lista de UUIDs
    	{SvPid, get_uuid, UUID} ->
    		IsDone = lists:member(UUID, ListaUUID),
    		SvPid ! {{get_uuid_res, UUID}, IsDone},
    		if
    			% Otro servidor va a realizar esa operacion
    			IsDone == false ->
    				bucle_recepcion(Servidores, Yo, BaseDatos, UpdatedUntil, ListaUUID ++ [UUID]);
    			% Esa operacion ya la he hecho yo
    			true ->
    				bucle_recepcion(Servidores, Yo, BaseDatos, UpdatedUntil, ListaUUID)
    		end;
        % Solicitud de lee, escribe o escribe_hash
        {ClPid, UUID, Op, Params} ->
            %io:format("~p recibe req ~p~n", [node(), UUID]),
        	MaxInstancia = paxos:max(Yo),
            {NewBaseDatos, NewUpdatedUntil} = simula_fallo_mensj_cliente({ClPid, UUID, Op, Params}, Servidores, Yo, BaseDatos, UpdatedUntil, MaxInstancia + 1, ListaUUID),
            %io:format("~p termina req ~p~n", [node(), UUID]),
            bucle_recepcion(Servidores, Yo, NewBaseDatos, NewUpdatedUntil, ListaUUID ++ [UUID]);
        _Msg ->
        	bucle_recepcion(Servidores, Yo, BaseDatos, UpdatedUntil, ListaUUID)
    end.
    
%%-----------------------------------------------------------------------------
simula_fallo_mensj_cliente(Mensaje, Servidores, Yo, BaseDatos, UpdatedUntil, NuInstancia, ListaUUID) ->
    Es_fiable = true,  % es_fiable(),
    Aleatorio = rand:uniform(1000),
      %si no fiable, eliminar mensaje con cierta aleatoriedad
    if  ((not Es_fiable) and (Aleatorio < 200)) -> 
                bucle_recepcion(Servidores, Yo, BaseDatos, UpdatedUntil, ListaUUID);
                  % Y si lo es tratar el mensaje recibido correctamente
        true ->
        	gestion_mnsj_cliente(Mensaje, Yo, BaseDatos, UpdatedUntil, NuInstancia, ListaUUID, Servidores)
    end.

%%-----------------------------------------------------------------------------
%% implementar tratamiento de mensajes recibidos en  servidor clave valor
gestion_mnsj_cliente(Mensaje, Yo, BaseDatos, UpdatedUntil, NuInstancia, ListaUUID, Servidores) ->
    case Mensaje of
        % Leer valor
        {ClPid, UUID, lee, {Clave}} ->
        	process_read_msg(Yo, ClPid, UUID, NuInstancia, Clave, BaseDatos, UpdatedUntil, ListaUUID, Servidores);
        % Escribir valor
        {ClPid, UUID, escribe, {Clave, Valor, false}} ->
            process_write_msg(Yo, ClPid, UUID, NuInstancia, Clave, Valor, BaseDatos, UpdatedUntil, ListaUUID, Servidores);
        % Escribir valor hash
        {ClPid, UUID, escribe, {Clave, Valor, true}} ->
            process_hash_write_msg(Yo, ClPid, UUID, NuInstancia, Clave, Valor, BaseDatos, UpdatedUntil, ListaUUID, Servidores);
        _ ->
            %%%%%%%%%
            % TO DO %
            %%%%%%%%%
            err
    end.

% Procesar peticion de cliente para leer valor
process_read_msg(Yo, ClPid, UUID, NuInstancia, Clave, BaseDatos, UpdatedUntil, ListaUUID, Servidores) ->
	V = {lee, Clave},
    {NewBaseDatos, NewUpdatedUntil} = esperar_consenso(Yo, NuInstancia, V, BaseDatos, UpdatedUntil, UUID, ListaUUID, Servidores, true),
    % Devolver resultado
    ReadVal = dict:find(Clave, NewBaseDatos),
    if
    	ReadVal == error ->
    		ResVal = "";
    	true ->
    		{ok, ResVal} = ReadVal
    end,
    ExpectedRes = {UUID, {Clave, ResVal}},
    ClPid ! ExpectedRes,
    {NewBaseDatos, NewUpdatedUntil}.

% Procesar peticion de cliente para escribir valor
process_write_msg(Yo, ClPid, UUID, NuInstancia, Clave, Valor, BaseDatos, UpdatedUntil, ListaUUID, Servidores) ->
	V = {escribe, Clave, Valor},
    {NewBaseDatos, NewUpdatedUntil} = esperar_consenso(Yo, NuInstancia, V, BaseDatos, UpdatedUntil, UUID, ListaUUID, Servidores, true),
    % Devolver resultado
    ExpectedRes = {UUID, {Clave, Valor}},
    ClPid ! ExpectedRes,
    {NewBaseDatos, NewUpdatedUntil}.

% Procesar peticion de cliente para escribir valor
process_hash_write_msg(Yo, ClPid, UUID, NuInstancia, Clave, Valor, BaseDatos, UpdatedUntil, ListaUUID, Servidores) ->
	{PrevVal, HashedVal} = concat_hash(BaseDatos, Clave, Valor),
    V = {escribe, Clave, HashedVal},
    {NewBaseDatos, NewUpdatedUntil} = esperar_consenso(Yo, NuInstancia, V, BaseDatos, UpdatedUntil, UUID, ListaUUID, Servidores, true),
    % Devolver resultado
    ExpectedRes = {UUID, {Clave, PrevVal}},
    ClPid ! ExpectedRes,
    {NewBaseDatos, NewUpdatedUntil}.

concat_hash(BaseDatos, Clave, NuevoValor) ->
    PrevVal = dict:find(Clave, BaseDatos),
    if
        PrevVal == error ->
            {"", integer_to_list(comun:hash(NuevoValor))};
        true ->
            {PrevVal, integer_to_list(comun:hash(lists:concat([PrevVal, NuevoValor])))}
    end.

% La operacion no se ha realizado en otro servidor pero la voy a realizar yo
wait_uuid_response(_ListaUUID, _UUID, 0) ->
	false;

% Espera a respuestas de otros servidores para saber si se ha realizado la operacion
wait_uuid_response(ListaUUID, UUID, N) ->
	Res = comun:get_msg({get_uuid_res, UUID}, ?TIMEOUT),
	if
		% Esperar respuestas de otros servidores
		(Res == false) or (Res == timeout) ->
			wait_uuid_response(ListaUUID, UUID, N-1);
		% Operacion ya esta hecha
		true ->
			true
	end.

check_uuid(ListaUUID, UUID, Servidores) ->
	IsDone = lists:member(UUID, ListaUUID),
	if
		% No lo he hecho yo previamente, comprobar si otro lo ha hecho
		IsDone == false ->
			lists:foreach(fun(Sv) ->
				{servidor, Sv} ! {self(), get_uuid, UUID}
			end, lists:subtract(Servidores, [node()])),
			wait_uuid_response(ListaUUID, UUID, length(Servidores) - 1);
		% Lo he hecho yo previamente
		true ->
			true
	end.

% Pregunta cada X tiempo si hay consenso sobre una instancia, siendo X cada vez mayor si no hay consenso
esperar_consenso(Yo, NuInstancia, ExpectedOp, BaseDatos, UpdatedUntil, UUID, ListaUUID, Servidores, CheckUUID) ->
	if
		CheckUUID == false ->
			% Iniciar instancia paxos para llegar a consenso
			paxos:start_instancia(Yo, NuInstancia, ExpectedOp),
		    esperar_consenso(Yo, NuInstancia, 100, ?MAX_ESPERA_CONSENSO * 1000, ExpectedOp, BaseDatos, UpdatedUntil, UUID, ListaUUID, Servidores);
		true ->
			% Comprobar que la operacion no se haya hecho con anterioridad en otro servidor
			IsDone = check_uuid(ListaUUID, UUID, Servidores),
			if
				% No se ha realizado la operacion con anterioridad
				IsDone == false ->
					% Iniciar instancia paxos para llegar a consenso
					paxos:start_instancia(Yo, NuInstancia, ExpectedOp),
				    esperar_consenso(Yo, NuInstancia, 100, ?MAX_ESPERA_CONSENSO * 1000, ExpectedOp, BaseDatos, UpdatedUntil, UUID, ListaUUID, Servidores);
				% La operacion ya se ha realizado en otro servidor
				true ->
					actualizar_bd(Yo, BaseDatos, UpdatedUntil, NuInstancia)
			end
	end.

esperar_consenso(Yo, NuInstancia, AfterSec, MaxEsperaConsenso, ExpectedOp, BaseDatos, UpdatedUntil, UUID, ListaUUID, Servidores) ->
    % Pregunta estado
    Valor = paxos:estado(Yo, NuInstancia),
    case Valor of
        % Si aun no hay consenso esperamos un tiempo determinado
        {false, _} ->
            if
                AfterSec > MaxEsperaConsenso ->
                    AfterSecAux = MaxEsperaConsenso;
                true ->
                    AfterSecAux = AfterSec
            end,
            timer:sleep(AfterSecAux),
            esperar_consenso(Yo, NuInstancia, AfterSec * 2, MaxEsperaConsenso, ExpectedOp, BaseDatos, UpdatedUntil, UUID, ListaUUID, Servidores);
        % Si ya hay consenso
        _ ->
            {true, ValorInstancia} = Valor,
            % Comprobar el valor sobre el cual se ha llegado a un consenso
            if
            	% Si hay consenso sobre la operacion deseada entonces se devuelve
            	ValorInstancia == ExpectedOp ->
            		actualizar_bd(Yo, BaseDatos, UpdatedUntil, NuInstancia);
            	% Si hay consenso sobre una operacion que no es la deseada entonces actualiza y lanza nueva instancia
            	true ->
            		{NewBaseDatos, NuInstancia} = actualizar_bd(Yo, BaseDatos, NuInstancia, NuInstancia),
            		% Esta vez no compruebo si la UUID la ha hecho otro servidor porque la voy a hacer yo
            		esperar_consenso(Yo, NuInstancia + 1, ExpectedOp, NewBaseDatos, UpdatedUntil, UUID, ListaUUID, Servidores, false)
            end
    end.

% Actualiza la base de datos desde la instancia From hasta la instancia To
actualizar_bd(Yo, BaseDatos, From, To) when From > To ->
    % Actualiza valor de hecho
    paxos:hecho(Yo, To),
	{BaseDatos, To};

actualizar_bd(Yo, BaseDatos, From, To) ->
	{Decidida, Valor} = paxos:estado(Yo, From),
    %io:format("~p instancia ~p decidida? ~p valor? ~p~n", [Yo, From, Decidida, Valor]),
	% Comprobamos que la instancia esta decidida
	if
		Decidida ->
			ValorInstancia = Valor;
		true ->
			ValorInstancia = no_decidida
	end,
	case ValorInstancia of
		% Si es una operacion de escritura entonces actualizo
		{escribe, RegClave, RegValor} ->
			%io:format("~p Actualizando BD ~p - ~p: ~p~n", [Yo, From, To, ValorInstancia]),
			NewBaseDatos = dict:store(RegClave, RegValor, BaseDatos),
			actualizar_bd(Yo, NewBaseDatos, From + 1, To);
		% Sino sigo con la siguiente operacion
		_ ->
			actualizar_bd(Yo, BaseDatos, From + 1, To)
	end.