-module(compile_check_ffi).
-export([shell/1]).

shell(Cmd) ->
    Output = os:cmd(binary_to_list(Cmd)),
    % gleam's diagnostics contain box-drawing characters, so the raw charlist
    % may hold codepoints above 255 that list_to_binary/1 rejects.
    case unicode:characters_to_binary(Output, utf8) of
        Bin when is_binary(Bin) -> Bin;
        _ -> unicode:characters_to_binary(Output, latin1)
    end.
