-module(test_network).

-export([request/3]).

request(_APIKey, _Endpoint, _Input) ->
    erlang:display("using the test network client"),
    % this only works when running tests from the root statsig_ex directory
    Path = filename:absname("test/data/simple_config.json"),
    case file:read_file(Path) of
        {ok, Body} ->
            Body;
        {error, Reason} ->
            io:format("Failed to read file: ~p~n", [Reason]),
            false
    end.
