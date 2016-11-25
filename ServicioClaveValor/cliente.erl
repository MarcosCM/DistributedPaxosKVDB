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


-define(TIMEOUT, 10).

-define(TIEMPO_PROCESADO_PAXOS, 1000).

-define(PRINT(Texto,Datos), io:format(Texto,Datos)).
%-define(PRINT(Texto,Datos), ok)).

-define(ENVIO(Mensj, Dest),
        io:format("~p -> ~p -> ~p~n",[node(), Mensj, Dest]), Dest ! Mensj).
%-define(ENVIO(Mensj, Dest), Dest ! Mensj).

-define(ESPERO(Dato), Dato -> io:format("LLega ~p-> ~p~n",[Dato,node()]), ).
%-define(ESPERO(Dato), Dato -> ).



%%%%%%%%%%%% FUNCIONES EXPORTABLES


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%  Poner en marcha un nodo cliente
%%  Devuelve :  el nombre completo del nodo erlang.
%% La especificación del interfaz de la función es la siguiente :
%%                      (se puede utilizar también para "dialyzer")
-spec start( [ atom() ], atom(), atom() ) -> node().
start(Servidores, Host, NombreNodo) ->
    io:format("Arrancar un nodo cliente  de servicio clave/valor~n",[]),
    
     % args para comando remoto erl
    Args = "-connect_all false -setcookie palabrasecreta" ++ 
                                            " -pa ./Paxos ./ServicioClaveValor",

        % arranca cliente clave/valor en nodo remoto
    {ok, Nodo} = slave:start(Host, NombreNodo, Args),
    io:format("Nodo cliente en marcha~n",[]),
    process_flag(trap_exit, true),
    spawn_link(Nodo, ?MODULE, init, [Servidores,Nodo]),
    Nodo.
    

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Parar nodo Erlang remoto
-spec stop(atom()) -> ok.
stop(Nodo) ->
    slave:stop(Nodo),
    timer:sleep(10),
    comun:vaciar_buzon(),
    ok.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Obtener el valor en curso de la clave
%% - Devuelve cadena vacia de caracteres ("") si no existe la clave
%% - Seguir intentandolo  en el resto de situaciones de fallo o error
%% La especificación del interfaz de la función es la siguiente :
%%                      (se puede utilizar también para "dialyzer")
-spec lee( node(), string() ) -> string().
lee(NodoCliente, Clave) ->

            %%%%% VUESTRO CODIGO AQUI


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Escribir un valor para una clave
%% - Seguir intentandolo hasta que se tenga exito
%% - Devuelve valor anterior si hash y nuevo sino
%% La especificación del interfaz de la función es la siguiente :
%%                      (se puede utilizar también para "dialyzer")
-spec escribe_generico( node(), string(), string(), boolean ) -> string().
escribe_generico(NodoCliente, Clave, Valor, ConHash) ->
     
            %%%%% VUESTRO CODIGO AQUI
    


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
init(Servidores, Yo) ->
    register(cliente, self()),
    
       
    %%%%% VUESTRO CODIGO DE INICIALIZACION AQUI
    

    bucle_recepcion(Servidores, Yo).
    
    
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
bucle_recepcion(Servidores, Yo) ->
    
            %%%%% VUESTRO CODIGO AQUI
    
 
