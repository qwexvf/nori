-module(store_ffi).
-export([create_table/0]).

create_table() ->
    case ets:whereis(todo_store) of
        undefined ->
            ets:new(todo_store, [set, public, named_table]);
        Ref ->
            Ref
    end.
