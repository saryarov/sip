-module(sip_serv_monitor_tests).
-include_lib("eunit/include/eunit.hrl").
-include("sip_serv_records.hrl").

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
    ets:delete_all_objects(registration_cache),
    ets:delete_all_objects(subscription_cache),
    file:make_dir("logs"),
    ok.

%%--------------------------------------------------------------------
%% get_count_stats
%%--------------------------------------------------------------------
get_count_stats_test() ->
    setup(),
    {Reg, Sub} = sip_serv_monitor:get_count_stats(),
    ?assert(is_integer(Reg)),
    ?assert(is_integer(Sub)),
    ?assert(Reg >= 0),
    ?assert(Sub >= 0).

%%--------------------------------------------------------------------
%% log_count_stats
%%--------------------------------------------------------------------
log_count_stats_test() ->
    setup(),
    File = "logs/test_count.log",
    file:delete(File),

    Result = sip_serv_monitor:log_count_stats(File),
    ?assertEqual(ok, Result),
    ?assert(filelib:is_file(File)),

    {ok, Bin} = file:read_file(File),
    ?assert(binary:match(Bin, <<"Active registrations">>) =/= nomatch),
    ?assert(binary:match(Bin, <<"Active subscriptions">>) =/= nomatch).

%%--------------------------------------------------------------------
%% log_full_stats
%%-------------------------------------------------------------------
log_full_stats_test() ->
    setup(),
    File = "logs/test_full.log",
    file:delete(File),

    Now = erlang:system_time(second),
    Reg = #registration{
        aor = "user1@localhost",
        contact = "sip:user1@127.0.0.1",
        expires_time = Now + 60,
        registered_time = Now
    },
    sip_serv_cache:put_registration(Reg),

    Result = sip_serv_monitor:log_full_stats(File),
    ?assertEqual(ok, Result),
    ?assert(filelib:is_file(File)),

    {ok, Bin} = file:read_file(File),
    ?assert(binary:match(Bin, <<"user1@localhost">>) =/= nomatch).