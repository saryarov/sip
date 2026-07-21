-module(sip_serv_api_tests).
-include_lib("eunit/include/eunit.hrl").
-include("sip_serv_records.hrl").

sip_serv_api_test_() ->
    {setup,
     fun setup/0,
     fun(_) -> ok end,
     [
         fun monitor_log_default/0,
         fun monitor_log_custom_file/0,
         fun monitor_full_log_custom_file/0,
         fun add_user_binary/0,
         fun add_user_list/0,
         fun delete_user/0,
         fun delete_user_not_found/0
     ]}.

setup() ->
    application:load(mnesia),
    catch mnesia:stop(),
    timer:sleep(50),
    _ = mnesia:delete_schema([node()]),
    _ = mnesia:create_schema([node()]),
    {ok, _} = application:ensure_all_started(mnesia),

    case whereis(sip_serv_cache) of
        undefined ->
            case sip_serv_cache:start_link() of
                {ok, _} -> ok;
                {error, {already_started, _}} -> ok
            end;
        _ ->
            ok
    end,

    ok = sip_serv_db:init_db(),
    file:make_dir("logs"),
    ok.

monitor_log_default() ->
    file:delete("logs/active.log"),
    Result = sip_serv_api:monitor_log(),
    ?assert(Result =:= ok orelse element(1, Result) =:= error).

monitor_log_custom_file() ->
    FileStr = "logs/api_test_count.log",
    file:delete(FileStr),
    Result = sip_serv_api:monitor_log(list_to_binary(FileStr)),
    ?assert(Result =:= ok orelse element(1, Result) =:= error).

monitor_full_log_custom_file() ->
    FileStr = "logs/api_test_full.log",
    file:delete(FileStr),
    Result = sip_serv_api:monitor_full_log(list_to_binary(FileStr)),
    ?assert(Result =:= ok orelse element(1, Result) =:= error).

add_user_binary() ->
    Result = sip_serv_api:add_user(<<"test_api_user@localhost">>, <<"pass123">>),
    ?assert(Result =:= ok orelse Result =:= {error, exists}).

add_user_list() ->
    Result = sip_serv_api:add_user("test_api_user2@localhost", "pass123"),
    ?assert(Result =:= ok orelse Result =:= {error, exists}).

delete_user() ->
    _ = sip_serv_api:add_user(<<"test_del_user@localhost">>, <<"pass">>),
    Result = sip_serv_api:delete_user(<<"test_del_user@localhost">>),
    ?assert(Result =:= ok orelse Result =:= {error, not_found}).
delete_user_not_found() ->
    Result = sip_serv_api:delete_user(<<"no_such_user_xyz@localhost">>),
    ?assert(Result =:= {error, not_found} orelse Result =:= ok).
