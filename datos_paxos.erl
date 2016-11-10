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
		% dict NuRegistro -> Valor :: any()
            registros = dict:new(),
		% dict NuInstancia -> {Decidido :: boolean(), Valor :: any()}
			instancias = dict:new(),
		% pos_integer()
			hecho_hasta = 0
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

get_hecho_hasta(PaxosData) ->
	PaxosData#paxos.hecho_hasta.

set_hecho_hasta(PaxosData, NuInstancia) ->
	if
		NuInstancia < PaxosData#paxos.hecho_hasta ->
			PaxosData;
		true ->
			PaxosData#paxos{hecho_hasta = NuInstancia}
	end.
