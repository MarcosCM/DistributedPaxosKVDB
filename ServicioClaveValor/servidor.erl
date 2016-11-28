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


-define(TIMEOUT, 3).
-define(MAX_ESPERA_CONSENSO, 30).


-define(PRINT(Texto,Datos), io:format(Texto,Datos)).
%-define(PRINT(Texto,Datos), ok)).

-define(ENVIO(Mensj, Dest),
        io:format("~p -> ~p -> ~p~n",[node(), Mensj, Dest]), Dest ! Mensj).
%-define(ENVIO(Mensj, Dest), Dest ! Mensj).

-define(ESPERO(Dato), Dato -> io:format("LLega ~p-> ~p~n",[Dato,node()]), ).
%-define(ESPERO(Dato), Dato -> ).

%%%%%%%%%%%%%%%%%%%% FUNCIONES EXPORTABLES  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Poner en marcha un nodo Paxos
%% Devuelve :  el nombre completo del nodo erlang.
%% La especificación del interfaz de la función es la siguiente :
%%                      (se puede utilizar también para "dialyzer")
-spec start( [ atom() ], atom(), atom() ) -> node().
start(Servidores, Host, NombreNodo) ->
    io:format("Arrancar un nodo servidor C/V~n",[]),

    % args para comando remoto erl
    Args = "-connect_all false -setcookie \'palabrasecreta\'" ++ 
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
    bucle_recepcion(Servidores, Yo, BaseDatos, 0).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Parar nodo Erlang remoto
-spec stop( atom() ) -> ok.
stop(Nodo) ->
    slave:stop(Nodo),
    timer:sleep(10),
    comun:vaciar_buzon(),
    ok.
    
%%%%%%%%%%%%%%%%%  FUNCIONES LOCALES  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%  
    
%%-----------------------------------------------------------------------------
% UpdatedUntil indica hasta que numero de instancia esta actualizado este servidor
bucle_recepcion(Servidores, Yo, BaseDatos, UpdatedUntil) ->
    receive
        % Solicitud de lee, escribe o escribe_hash
        Mensaje_cliente ->
        	MaxInstancia = paxos:max(Yo),
            {NewBaseDatos, NewUpdatedUntil} = simula_fallo_mensj_cliente(Mensaje_cliente, Servidores, Yo, BaseDatos, UpdatedUntil, MaxInstancia + 1),
            % Actualizar hecho
            bucle_recepcion(Servidores, Yo, NewBaseDatos, NewUpdatedUntil)
    end.
    
%%-----------------------------------------------------------------------------
simula_fallo_mensj_cliente(Mensaje, Servidores, Yo, BaseDatos, UpdatedUntil, NuInstancia) ->
    Es_fiable = true,  % es_fiable(),
    Aleatorio = rand:uniform(1000),
      %si no fiable, eliminar mensaje con cierta aleatoriedad
    if  ((not Es_fiable) and (Aleatorio < 200)) -> 
                bucle_recepcion(Servidores, Yo, BaseDatos, UpdatedUntil);
                  % Y si lo es tratar el mensaje recibido correctamente
        true ->
        	gestion_mnsj_cliente(Mensaje, Yo, BaseDatos, UpdatedUntil, NuInstancia)
    end.

%%-----------------------------------------------------------------------------
%% implementar tratamiento de mensajes recibidos en  servidor clave valor
gestion_mnsj_cliente(Mensaje, Yo, BaseDatos, UpdatedUntil, NuInstancia) ->
    case Mensaje of
        % Leer valor
        {ClPid, lee, {Clave}} ->
            process_read_msg(Yo, ClPid, NuInstancia, Clave, BaseDatos, UpdatedUntil);
        % Escribir valor
        {ClPid, escribe, {Clave, Valor, false}} ->
            process_write_msg(Yo, ClPid, NuInstancia, Clave, Valor, BaseDatos, UpdatedUntil);
        % Escribir valor hash
        {ClPid, escribe, {Clave, Valor, true}} ->
            process_hash_write_msg(Yo, ClPid, NuInstancia, Clave, Valor, BaseDatos, UpdatedUntil);
        _ ->
            %%%%%%%%%
            % TO DO %
            %%%%%%%%%
            err
    end.

% Procesar peticion de cliente para leer valor
process_read_msg(Yo, ClPid, NuInstancia, Clave, BaseDatos, UpdatedUntil) ->
	V = {lee, Clave},
    {NewBaseDatos, NewUpdatedUntil} = esperar_consenso(Yo, NuInstancia, V, BaseDatos, UpdatedUntil),
    % Devolver resultado
    ReadVal = dict:find(Clave, NewBaseDatos),
    if
    	ReadVal == error ->
    		ResVal = "";
    	true ->
    		{ok, ResVal} = ReadVal
    end,
    ExpectedRes = {lee_res, {Clave, ResVal}},
    ClPid ! ExpectedRes,
    {NewBaseDatos, NewUpdatedUntil}.

% Procesar peticion de cliente para escribir valor
process_write_msg(Yo, ClPid, NuInstancia, Clave, Valor, BaseDatos, UpdatedUntil) ->
	V = {escribe, Clave, Valor},
    {NewBaseDatos, NewUpdatedUntil} = esperar_consenso(Yo, NuInstancia, V, BaseDatos, UpdatedUntil),
    % Devolver resultado
    ExpectedRes = {escribe_res, {Clave, Valor}},
    ClPid ! ExpectedRes,
    {NewBaseDatos, NewUpdatedUntil}.

% Procesar peticion de cliente para escribir valor
process_hash_write_msg(Yo, ClPid, NuInstancia, Clave, Valor, BaseDatos, UpdatedUntil) ->
	{PrevVal, HashedVal} = concat_hash(BaseDatos, Clave, Valor),
    V = {escribe, Clave, HashedVal},
    {NewBaseDatos, NewUpdatedUntil} = esperar_consenso(Yo, NuInstancia, V, BaseDatos, UpdatedUntil),
    % Devolver resultado
    ExpectedRes = {escribe_res, {Clave, PrevVal}},
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

% Pregunta cada X tiempo si hay consenso sobre una instancia, siendo X cada vez mayor si no hay consenso
esperar_consenso(Yo, NuInstancia, ExpectedOp, BaseDatos, UpdatedUntil) ->
	paxos:start_instancia(Yo, NuInstancia, ExpectedOp),
    esperar_consenso(Yo, NuInstancia, 1000, ?MAX_ESPERA_CONSENSO * 1000, ExpectedOp, BaseDatos, UpdatedUntil).

esperar_consenso(Yo, NuInstancia, AfterSec, MaxEsperaConsenso, ExpectedOp, BaseDatos, UpdatedUntil) ->
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
            esperar_consenso(Yo, NuInstancia, AfterSec * 2, MaxEsperaConsenso, ExpectedOp, BaseDatos, UpdatedUntil);
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
            		esperar_consenso(Yo, NuInstancia + 1, ExpectedOp, NewBaseDatos, UpdatedUntil)
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