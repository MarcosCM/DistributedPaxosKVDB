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

-compile(export_all).


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

printar_cola() ->
	printar_cola([]).

printar_cola(L) ->
	receive
		M ->
			io:format("~p~n", [M]),
			printar_cola(L ++ [M])
	after
		0 ->
			resend_msg_buff(L)
	end.

%% Reenviar mensajes almacenados en el buffer
resend_msg_buff([]) ->
	buff_empty;

resend_msg_buff([H|T]) ->
	self() ! H,
	resend_msg_buff(T).

%% Obtener mensaje de un tipo concreto con un tiempo de timeout
get_msg_aux(MsgType, MsgBuff, TimeOut) ->
	receive
		{MsgType, Data} ->
			resend_msg_buff(MsgBuff),
			Data;
		Msg ->
			get_msg_aux(MsgType, MsgBuff ++ [Msg], TimeOut)
	after TimeOut ->
		resend_msg_buff(MsgBuff),
		timeout
	end.

%% Obtener mensaje de un tipo concreto con tiempo de timeout
get_msg(MsgType, TimeOut) ->
	get_msg_aux(MsgType, [], TimeOut).

%% Obtener mensaje de un tipo concreto sin tiempo de timeout
get_msg_aux(MsgType, MsgBuff) ->
	receive
		{MsgType, Data} ->
			resend_msg_buff(MsgBuff),
			Data;
		Msg ->
			get_msg_aux(MsgType, MsgBuff ++ [Msg])
	end.

%% Obtener mensaje de un tipo concreto sin tiempo de timeout
get_msg(MsgType) ->
	get_msg_aux(MsgType, []).