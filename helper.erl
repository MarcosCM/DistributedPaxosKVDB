-module(helper).
-compile(export_all).
-export([killall/0]).

killall() ->
    erlang:disconnect_node('n1@127.0.0.1'),
    erlang:disconnect_node('n2@127.0.0.1'),
    erlang:disconnect_node('n3@127.0.0.1'),
    erlang:disconnect_node('n4@127.0.0.1'),
    erlang:disconnect_node('n5@127.0.0.1'),
    erlang:disconnect_node('n6@127.0.0.1').