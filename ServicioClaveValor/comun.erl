%% ----------------------------------------------------------------------------
%% Modulo: comun
%%
%% Descripcion : Elementos comunes de cliente y servidor
%%
%% Esqueleto por : Unai Arronategui
%% Autor : Marcos Canales Mayo
%%
%% ----------------------------------------------------------------------------

-module(comun).

-export([hash/1, vaciar_buzon/0]).


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Obtener el hash de un string (lista de caracteres en erlang)
%% - Devuelve un entero de 32 bits
hash(String_concatenado) ->
    erlang:phash2(String_concatenado).
    
    
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Vaciar buzon de proceso en curso, tambien llamado en otros sitios flush()
vaciar_buzon() ->
    receive _ -> vaciar_buzon()
    after   0 -> ok
    end.

