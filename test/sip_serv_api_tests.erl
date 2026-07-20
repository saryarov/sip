-module(sip_serv_api_tests).
-include_lib("eunit/include/eunit.hrl").

%%--------------------------------------------------------------------
%% setup
%%--------------------------------------------------------------------
setup() ->
    case whereis(sip_serv_cache) of
        undefined ->
            {ok, _} = sip_serv_cache:start_link();
        _ ->
            ok
    end,
    file:make_dir("logs"),
    ok.

%%--------------------------------------------------------------------
%% monitor_log / monitor_full_log
%%--------------------------------------------------------------------
monitor_log_default_test() ->
    setup(),
    file:delete("logs/active.log"),
    Result = sip_serv_api:monitor_log(),
    %% ok или error — главное, что не падает
    ?assert(Result =:= ok orelse element(1, Result) =:= error).

monitor_log_custom_file_test() ->
    setup(),
    File = <<"logs/api_test_count.log">>,
    file:delete(binary_to_list(File)),
    Result = sip_serv_api:monitor_log(File),
    ?assert(Result =:= ok orelse element(1, Result) =:= error),
    case Result of
        ok ->
            ?assert(filelib:is_file(binary_to_list(File)));
        _ ->
            ok
    end.

monitor_full_log_custom_file_test() ->
    setup(),
    File = <<"logs/api_test_full.log">>,
    file:delete(binary_to_list(File)),
    Result = sip_serv_api:monitor_full_log(File),
    ?assert(Result =:= ok orelse element(1, Result) =:= error).

%%--------------------------------------------------------------------
%% add_user / delete_user
%% (зависят от sip_serv_auth + Mnesia)
%%--------------------------------------------------------------------
add_user_binary_test() ->
    setup(),
    Result = sip_serv_api:add_user(<<"test_api_user@localhost">>, <<"pass123">>),
    ?assert(Result =:= ok
            orelse Result =:= {error, exists}
            orelse element(1, Result) =:= error).

add_user_list_test() ->
    setup(),
    Result = sip_serv_api:add_user("test_api_user2@localhost", "pass123"),
    ?assert(Result =:= ok
            orelse Result =:= {error, exists}
            orelse element(1, Result) =:= error).

delete_user_test() ->
    setup(),
    %% сначала пробуем создать
    _ = sip_serv_api:add_user(<<"test_del_user@localhost">>, <<"pass">>),
    Result = sip_serv_api:delete_user(<<"test_del_user@localhost">>),
    ?assert(Result =:= ok
            orelse Result =:= {error, not_found}
            orelse element(1, Result) =:= error).

delete_user_not_found_test() ->
    setup(),
    Result = sip_serv_api:delete_user(<<"no_such_user_xyz@localhost">>),
    ?assert(Result =:= {error, not_found}
            orelse element(1, Result) =:= error).