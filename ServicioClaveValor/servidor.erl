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


-define(PRINT(Texto,Datos), io:format(Texto,Datos)).
%-define(PRINT(Texto,Datos), ok)).

-define(ENVIO(Mensj, Dest),
        io:format("~p -> ~p -> ~p~n",[node(), Mensj, Dest]), Dest ! Mensj).
%-define(ENVIO(Mensj, Dest), Dest ! Mensj).

-define(ESPERO(Dato), Dato -> io:format("LLega ~p-> ~p~n",[Dato,node()]), ).
%-define(ESPERO(Dato), Dato -> ).


%% Estructura de datos que representa una operación
 -record(op, {campos...

    % RELLENAR CON CAMPOS que necesitais para representar elementos operación
    
        }).


%%%%%%%%%%%%%%%%%%%% FUNCIONES EXPORTABLES  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Poner en marcha un nodo Paxos
%% Devuelve :  el nombre completo del nodo erlang.
%% La especificación del interfaz de la función es la siguiente :
%%                      (se puede utilizar también para "dialyzer")
-spec start( [ atom() ], atom(), atom() ) -> node().
start(Servidores, Host, NombreNodo) ->
    io:format("Arrancar un nodo servidor C/V~n",[]),

    %%%%% VUESTRO CODIGO DE INICIALIZACION
    
     % args para comando remoto erl
    Args = "-connect_all false -setcookie palabrasecreta" ++ 
                                            " -pa ./Paxos ./ServicioClaveValor",
        % arranca servidor en nodo remoto
    {ok, Nodo} = slave:start(Host, NombreNodo, Args),
    io:format("Nodo esclavo servidor C/V en marcha~n",[]),
    process_flag(trap_exit, true),
    spawn_link(Nodo, ?MODULE, init, [Servidores,Nodo]),
%    paxos:start( Servidores, Host, NombreNodo),
    Nodo.


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
init(Servidores, Yo) ->
    register(servidor, self()),
    
    
    %%%%% VUESTRO CODIGO DE INICIALIZACION AQUI
    
        
    bucle_recepcion(Servidores, Yo).
    
    
%%-----------------------------------------------------------------------------
bucle_recepcion(Servidores, Yo) ->
    receive

            
            %%%%% VUESTRO CODIGO AQUI

             
        Mensaje_cliente ->
            simula_fallo_mensj_cliente(Mensaje_cliente, Servidores, Yo)
    end.
    
%%-----------------------------------------------------------------------------
simula_fallo_mensj_cliente(Mensaje, Servidores, Yo) ->
    Es_fiable = true,  % es_fiable(),
    Aleatorio = rand:uniform(1000),
      %si no fiable, eliminar mensaje con cierta aleatoriedad
    if  ((not Es_fiable) and (Aleatorio < 200)) -> 
                bucle_recepcion(Servidores, Yo);
                  % Y si lo es tratar el mensaje recibido correctamente
        true -> gestion_mnsj_cliente(Mensaje, Servidores, Yo)
    end.


%%-----------------------------------------------------------------------------
%% implementar tratamiento de mensajes recibidos en  servidor clave valor
gestion_mnsj_cliente( Mensaje, Servidores, Yo) ->

    %%%%% VUESTRO CODIGO AQUI
    



