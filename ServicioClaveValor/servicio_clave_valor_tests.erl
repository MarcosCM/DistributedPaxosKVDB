%% ----------------------------------------------------------------------------
%% Modulo: servicio_clave_valor_tests
%%
%% Descripcion : Tests para verificar correcto funcionamiento del servicio clave/valor
%%
%% Esqueleto por : Unai Arronategui
%% Autor : Marcos Canales Mayo
%%
%% ----------------------------------------------------------------------------

-module(servicio_clave_valor_tests).
-include_lib("eunit/include/eunit.hrl").

-compile(export_all).

-define(HOST, '127.0.0.1').

-define(T_ESPERA, 100).



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% devueve lista de nombres de servidores a partir de lista númerica
servidores(Lista_Num) ->
    [ list_to_atom(lists:concat([s, X, '@', ?HOST]) ) || X <- Lista_Num ].
    
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
comprobar(NodoCliente, Clave, ValorAComprobar) ->
    ValorEnBD = cliente:lee(NodoCliente, Clave),
    if ValorEnBD /=  ValorAComprobar ->
        ?debugFmt("Error escribe; ~p esperado y ~p obtenido~n",
                    [ValorAComprobar,ValorEnBD]),
        exit("2 : Terminan tests por diferir valor en almacen y provisto!!!");
        
        true -> ok

    end.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% 
-spec siguiente_valor(string(), string() ) -> string().
siguiente_valor(Previo, Actual) ->
    H = comun:hash(Previo ++ Actual),
    integer_to_list(H).
    
    
%%%%%%%%%%%%%%%%%%%  FUNCIONES DE TEST %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
operaciones_basicas() ->
    ?debugFmt("Test: lee, escribe y escribe_hash basicos ...~n",[]),
    
   % Crear 3 servidores clave/valor
    NumServ = 3,
    LN = lists:seq(1,NumServ),
    S = servidores(LN),
    lists:foreach(fun(X) -> servidor:start(S,?HOST,lists:concat([s,X])) end, LN),
    
    % Crear 1 nodo cliente que trate con todos los servidores clave/valor
    C_global = cliente:start(S, ?HOST, c_glob),
    
    % Crear 3 nodos cliente que trate cada uno con solo un servidor clave/valor
    L_C = [ cliente:start( [ lists:nth(X, S) ], ?HOST,lists:concat([c,X]))
            ||  X <- LN ],
    
    timer:sleep(?T_ESPERA),
    
    ValorPrevio = cliente:escribe_hash(C_global, "a", "x"),

    if ValorPrevio =/= "" ->
        exit("1 : Terminan tests por diferir valor en almacen y provisto!!!");
       true -> ok
    end,
    
    cliente:escribe(C_global, "a", "aa"),
    comprobar(C_global, "a", "aa"),

    cliente:escribe(lists:nth(1,L_C), "a", "aaa"),
    
    comprobar(lists:nth(2,L_C), "a", "aaa"),
    comprobar(lists:nth(1,L_C), "a", "aaa"),
    comprobar(C_global, "a", "aaa"),

    
    % parar VMs Erlang
    lists:foreach(fun(X) -> servidor:stop(X) end, S ),
    lists:foreach(fun(X) -> cliente:stop(X) end, L_C ),

    ?debugFmt(".... Superado~n",[]).  
    

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
clientes_concurrentes() ->
    ?debugFmt("Test: clientes concurrentes ...~n",[]),
    
   % Crear 3 servidores clave/valor
    N_S = 3,
    LN = lists:seq(1,N_S), 
    S = servidores(LN),
    lists:foreach(fun(X) -> servidor:start(S,?HOST,lists:concat([s,X])) end, LN),
    
    % Crear 3 nodos cliente que trate cada uno con solo un servidor clave/valor
    C_Fijos = [ cliente:start( [ lists:nth(X, S) ], ?HOST,lists:concat([c,X]))
            || X <- LN ],
        
    % Realizar X iteraciones, de 15 clientes concurrentes cada una
    lists:foreach(fun(_X) -> clientes_15(N_S, S, C_Fijos) end,
                  lists:seq(1,20)),

    % parar VMs Erlang
    lists:foreach(fun(X) -> servidor:stop(X) end, S ),
    lists:foreach(fun(X) -> cliente:stop(X) end, C_Fijos),

    ?debugFmt(".... Superado~n",[]).  


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
clientes_15(N_S, S, C_Fijos) ->
    % Crear 15 nodos cliente que trate cada uno con solo un servidor aleatorio
    % Y que escriban o lean aleatoriamente
    L_Nu_Clientes = lists:seq(4,19),
    process_flag(trap_exit, true),
    lists:foreach(fun(X) ->
                        spawn_link(?MODULE, nuevo_cliente_op_rand, [X, N_S, S])
                  end, 
                  L_Nu_Clientes ),
                  
    % Esperar la terminación de todos los clientes
    lists:foreach(fun(_X) ->
                        receive  {'EXIT', _Pid, _Message} -> ok end
                  end,
                  L_Nu_Clientes ),
                  
    % verificar que todos los servidores tienen el mismo valor
    Valor_Cliente1 = cliente:lee(lists:nth(1, C_Fijos), "b"),
    Valor_Cliente2 = cliente:lee(lists:nth(2, C_Fijos), "b"),
    Valor_Cliente3 = cliente:lee(lists:nth(3, C_Fijos), "b"),
    if Valor_Cliente1 =/= Valor_Cliente2 ->
            exit("No corresponden los valores de clave b");
       true ->
            if Valor_Cliente1 =/= Valor_Cliente3 ->
                    exit("No corresponden los valores de clave b");
               true -> ok
            end
    end.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
nuevo_cliente_op_rand(Num_Cliente, N_S, S) ->
    N =cliente:start( [ lists:nth(rand:uniform(N_S), S) ],
                                        ?HOST,lists:concat([c,Num_Cliente])),
    
    timer:sleep(?T_ESPERA),

    Aleatorio = rand:uniform(1000),
    if  Aleatorio < 500 ->
            StringAleatorio = integer_to_list(rand:uniform(10000)),
            cliente:escribe(N, "b", StringAleatorio);
            
        true ->
            cliente:lee(N, "b")
    end,
                    
    cliente:stop(N),
    timer:sleep(?T_ESPERA).


%%%%%%%%%%%%%%%%% GENERADORES DE TEST %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

tests() ->
    operaciones_basicas(),
    clientes_concurrentes().

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% 
pruebas_test_() ->
    {inorder,
            [{spawn, {timeout, 6, ?_test(operaciones_basicas())}},
             {spawn, {timeout, 90, ?_test(clientes_concurrentes())}}
            ]}.
