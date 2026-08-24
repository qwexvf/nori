-module(cli_ffi).
-export([read_stdin/0]).

%% Read the whole of standard input as a UTF-8 binary (a Gleam String).
read_stdin() ->
    read_stdin(standard_io, []).

read_stdin(Device, Acc) ->
    case io:get_line(Device, "") of
        eof ->
            unicode:characters_to_binary(lists:reverse(Acc));
        {error, _} ->
            unicode:characters_to_binary(lists:reverse(Acc));
        Line ->
            read_stdin(Device, [Line | Acc])
    end.
