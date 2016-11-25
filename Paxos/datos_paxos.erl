%% ----------------------------------------------------------------------------
%% Modulo: datos_paxos
%%
%% Descripcion : Estructura de datos utilizada en el algoritmo Paxos y funciones auxiliares
%%
%% Esqueleto por : Unai Arronategui
%% Autor : Marcos Canales Mayo
%%
%% ----------------------------------------------------------------------------

-module(datos_paxos).
-compile(export_all).

		% atom
-record(paxos, {fiabilidad = fiable,
		% pos_integer()
            num_mensajes = 0,
		% [pid()]
            servidores = [],
		% pid()
            yo,
		% dict NuRegistro :: pos_integer() -> Valor :: any()
            registros = dict:new(),
		% dict NuInstancia :: pos_integer() -> {Decidido :: boolean(), Valor :: any()}
			instancias = dict:new(),
		% dict Servidor :: pos_integer() -> NuInstancia :: pos_integer()
			hecho = dict:new()
		}).

%%%%%%%%%%% FUNCIONES DE ACCESO Y MANIPULACION DE LA ESTRUCTURA DE DATOS
new_paxos_data(Servidores, Yo) ->
	#paxos{servidores=Servidores, yo=Yo}.

remove_instancia(PaxosData, NuInstancia) ->
	PaxosData#paxos{instancias = dict:erase(NuInstancia, PaxosData#paxos.instancias)}.

set_registro(PaxosData, NuRegistro, Valor) ->
	PaxosData#paxos{registros = dict:store(NuRegistro, Valor, PaxosData#paxos.registros)}.

remove_registro(PaxosData, NuRegistro) ->
	PaxosData#paxos{registros = dict:erase(NuRegistro, PaxosData#paxos.registros)}.

get_fiabilidad(PaxosData) ->
	PaxosData#paxos.fiabilidad.

set_fiabilidad(PaxosData, Fiabilidad) ->
	PaxosData#paxos{fiabilidad = Fiabilidad}.

get_num_mensajes(PaxosData) ->
	PaxosData#paxos.num_mensajes.

get_servidores(PaxosData) ->
	PaxosData#paxos.servidores.

get_yo(PaxosData) ->
	PaxosData#paxos.yo.

get_registros(PaxosData) ->
	PaxosData#paxos.registros.

get_instancias(PaxosData) ->
	PaxosData#paxos.instancias.

get_instancia(PaxosData, NuInstancia) ->
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
	end.

set_instancia(PaxosData, NuInstancia, Valor) ->
	PaxosData#paxos{instancias = dict:store(NuInstancia, Valor, PaxosData#paxos.instancias)}.

get_hecho(PaxosData) ->
	PaxosData#paxos.hecho.

hecho_clean_instancias(PaxosData) ->
	Min_hecho = get_min_hecho(PaxosData),
	dict:filter(fun(Key, _Value) ->
		Key > Min_hecho
	end, PaxosData#paxos.instancias).

set_hecho(PaxosData, Servidor, NuInstancia) ->
	SvHecho = dict:find(Servidor, PaxosData#paxos.hecho),
	if
		% No existe entrada
		SvHecho == error ->
			% En dos pasos, dado que para limpiar instancias es primero necesario tener los valores de hecho actualizados
			PaxosDataHechoUpd = PaxosData#paxos{hecho = dict:store(Servidor, NuInstancia, PaxosData#paxos.hecho)},
			PaxosDataHechoUpd#paxos{instancias = hecho_clean_instancias(PaxosData)};
		% Existe entrada
		true ->
			{ok, Val} = SvHecho,
			if
				% Los mensajes pueden llegar fuera de orden, por lo que esta comprobacion es necesaria
				NuInstancia =< Val ->
					PaxosData;
				true ->
					% En dos pasos, dado que para limpiar instancias es primero necesario tener los valores de hecho actualizados
					PaxosDataHechoUpd = PaxosData#paxos{hecho = dict:store(Servidor, NuInstancia, PaxosData#paxos.hecho)},
					PaxosDataHechoUpd#paxos{instancias = hecho_clean_instancias(PaxosData)}
			end
	end.

get_min_hecho_aux([], Min_hecho) ->
	if
		Min_hecho == none ->
			0;
		true ->
			Min_hecho
	end;

get_min_hecho_aux([{Key, Value}|T], Min_hecho) ->
	%io:format("~p tiene hecho ~p~n", [Key, Value]),
	if
		Min_hecho == none ->
			get_min_hecho_aux(T, Value);
		Value < Min_hecho ->
			get_min_hecho_aux(T, Value);
		true ->
			get_min_hecho_aux(T, Min_hecho)
	end.

get_min_hecho(PaxosData) ->
	ListaHecho = dict:to_list(PaxosData#paxos.hecho),
	get_min_hecho_aux(ListaHecho, none).