%% ----------------------------------------------------------------------------
%% paxos : Modulo la estructura de datos principal de Paxos
%%
%% 
%% 
%% 
%% 
%% ----------------------------------------------------------------------------


-module(datos_paxos).
-compile(export_all).

		% atom
-record(paxos, {fiabilidad = fiable,
		% pos_integer
            num_mensajes = 0,
		% [Pid]
            servidores = [],
		% Pid
            yo,
		% dict NuRegistro -> Valor :: any()
            registros = dict:new(),
		% dict NuInstancia -> {Decidido :: boolean(), Valor :: any()}
			instancias = dict:new()
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

set_instancia(PaxosData, NuInstancia, Valor) ->
	PaxosData#paxos{instancias = dict:store(NuInstancia, Valor, PaxosData#paxos.instancias)}.