%% ----------------------------------------------------------------------------
%% Modulo: cliente
%%
%% Descripcion : API cliente del servicio de almacen distribuido clave/valor
%%
%% Esqueleto por : Unai Arronategui
%% Autor : Marcos Canales Mayo
%%
%% ----------------------------------------------------------------------------

-module(cliente).

-export([start/3, stop/1, lee/2, escribe/3, escribe_hash/3]).

-export([init/2]).

-export([servidor_request/5]).

-define(TIMEOUT, 10).

-define(TIEMPO_PROCESADO_PAXOS, 500).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%  Poner en marcha un nodo cliente
%%  Devuelve :  el nombre completo del nodo erlang.
%% La especificación del interfaz de la función es la siguiente :
%%                      (se puede utilizar también para "dialyzer")
-spec start( [ atom() ], atom(), atom() ) -> node().
start(Servidores, Host, NombreNodo) ->
    io:format("Arrancar un nodo cliente de servicio clave/valor~n",[]),
    
     % args para comando remoto erl
    Args = "-connect_all false -setcookie palabrasecreta" ++ 
                                            " -pa ./Paxos ./ServicioClaveValor",

        % arranca cliente clave/valor en nodo remoto
    {ok, Nodo} = slave:start(Host, NombreNodo, Args),
    io:format("Nodo cliente en marcha~n",[]),
    process_flag(trap_exit, true),
    spawn_link(Nodo, ?MODULE, init, [Servidores, Nodo]),
    Nodo.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
init(Servidores, Yo) ->
    register(cliente, self()),
    
    bucle_recepcion(Servidores, Yo).


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Parar nodo Erlang remoto
-spec stop(atom()) -> ok.
stop(Nodo) ->
    slave:stop(Nodo),
    timer:sleep(10),
    comun:vaciar_buzon(),
    ok.

% Solicitar al servidor que ejecute una operación
servidor_request(ClPid, UUID, Op, Params, Servidores) ->
	servidor_request(ClPid, UUID, Op, Params, Servidores, ?TIEMPO_PROCESADO_PAXOS).

servidor_request(ClPid, UUID, _Op, _Params, [], _TimeOut) ->
	Res = comun:get_msg(UUID),
	ClPid ! {UUID, {element(1, Res), element(2, Res)}};

servidor_request(ClPid, UUID, Op, Params, [H|T], TimeOut) ->
    {servidor, H} ! {ClPid, UUID, Op, Params},
    Res = comun:get_msg(UUID, TimeOut),
    if
        Res == timeout ->
            servidor_request(ClPid, UUID, Op, Params, T, TimeOut);
        true ->
            ClPid ! {UUID, {element(1, Res), element(2, Res)}}
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Obtener el valor en curso de la clave
%% - Devuelve cadena vacia de caracteres ("") si no existe la clave
%% - Seguir intentandolo  en el resto de situaciones de fallo o error
%% La especificación del interfaz de la función es la siguiente :
%%                      (se puede utilizar también para "dialyzer")
-spec lee( node(), string() ) -> string().
lee(NodoCliente, Clave) ->
	% Identificador unico para esta operacion
	UniqueInt = erlang:unique_integer([monotonic]),
	UUID = erlang:phash2({UniqueInt, node()}),
	{cliente, NodoCliente} ! {self(), get_servidores},
	Servidores = comun:get_msg(get_servidores_res),
    servidor_request(self(), UUID, lee, {Clave}, Servidores),
    Res = comun:get_msg(UUID),
    {_ResClave, ResValor} = Res,
    ResValor.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Escribir un valor para una clave
%% - Seguir intentandolo hasta que se tenga exito
%% - Devuelve valor anterior si hash y nuevo sino
%% La especificación del interfaz de la función es la siguiente :
%%                      (se puede utilizar también para "dialyzer")
-spec escribe_generico( node(), string(), string(), boolean ) -> string().
escribe_generico(NodoCliente, Clave, Valor, ConHash) ->
	% Identificador unico para esta operacion
	UniqueInt = erlang:unique_integer([monotonic]),
	UUID = erlang:phash2({UniqueInt, node()}),
	{cliente, NodoCliente} ! {self(), get_servidores},
	Servidores = comun:get_msg(get_servidores_res),
	servidor_request(self(), UUID, escribe, {Clave, Valor, ConHash}, Servidores),
    Res = comun:get_msg(UUID),
    {_ResClave, ResValor} = Res,
    ResValor.
    

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% - Devuelve nuevo valor escrito
-spec escribe( node(), string(), string() ) -> string().
escribe(NodoCliente, Clave, Valor) ->
    escribe_generico(NodoCliente, Clave, Valor, false).


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% - Devuelve valor anterior
-spec escribe_hash( node(), string(), string() ) -> string().
escribe_hash(NodoCliente, Clave, Valor) ->
    escribe_generico(NodoCliente, Clave, Valor, true).
    

%%%%%%%%%%%%%%%%%%%%%%%%%%  FUNCIONES LOCALES

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
bucle_recepcion(Servidores, Yo) ->
    receive
    	{Pid, get_servidores} ->
    		Pid ! {get_servidores_res, Servidores},
    		bucle_recepcion(Servidores, Yo);
        Msg ->
            io:format("err, msg: ~p~n", [Msg]),
            bucle_recepcion(Servidores, Yo)
    end.