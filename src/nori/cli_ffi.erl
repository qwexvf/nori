-module(cli_ffi).
-export([read_stdin/0, run_executable/2]).

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

%% Run an executable found on PATH with the given arguments, without a shell,
%% and return its combined output. Error(nil) when it is not on PATH.
run_executable(Name, Args) ->
    case os:find_executable(binary_to_list(Name)) of
        false ->
            {error, nil};
        Path ->
            Port = open_port({spawn_executable, Path},
                             [{args, [binary_to_list(A) || A <- Args]},
                              exit_status, stderr_to_stdout, binary]),
            collect(Port, [])
    end.

collect(Port, Acc) ->
    receive
        {Port, {data, Data}} ->
            collect(Port, [Data | Acc]);
        {Port, {exit_status, Status}} ->
            {ok, {Status, iolist_to_binary(lists:reverse(Acc))}}
    end.
