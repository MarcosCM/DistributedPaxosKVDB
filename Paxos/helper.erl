%% ----------------------------------------------------------------------------
%% Modulo: helper
%%
%% Descripcion : Ayuda para ejecutar los tests
%%
%% Autor: Marcos Canales Mayo 
%%
%% ----------------------------------------------------------------------------

-module(helper).
-compile(export_all).
-export([killall/0]).

killall() ->
    erlang:disconnect_node('n1@127.0.0.1'),
    erlang:disconnect_node('n2@127.0.0.1'),
    erlang:disconnect_node('n3@127.0.0.1'),
    erlang:disconnect_node('n4@127.0.0.1'),
    erlang:disconnect_node('n5@127.0.0.1'),
    erlang:disconnect_node('n6@127.0.0.1'),
    erlang:disconnect_node('s1@127.0.0.1'),
    erlang:disconnect_node('s2@127.0.0.1'),
    erlang:disconnect_node('s3@127.0.0.1'),
    erlang:disconnect_node('s4@127.0.0.1'),
    erlang:disconnect_node('s5@127.0.0.1'),
    erlang:disconnect_node('s6@127.0.0.1'),
    nodes_reset.