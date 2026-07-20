-module(sip_serv_cache_tests).
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
    ets:delete_all_objects(abonent_cache),
    ets:delete_all_objects(registration_cache),
    ets:delete_all_objects(subscription_cache),
    ets:delete_all_objects(publication_cache),
    ok.

%%--------------------------------------------------------------------
%% Abonent
%%--------------------------------------------------------------------
abonent_put_get_test() ->
    setup(),
    Ab = #abonent{aor = "user1@localhost", password = "pass"},
    ?assertEqual(true, sip_serv_cache:put_abonent(Ab)),
    ?assertMatch({ok, #abonent{aor = "user1@localhost", password = "pass"}},
                 sip_serv_cache:get_abonent("user1@localhost")).

abonent_not_found_test() ->
    setup(),
    ?assertEqual({error, not_found},
                 sip_serv_cache:get_abonent("nobody@localhost")).

abonent_delete_test() ->
    setup(),
    Ab = #abonent{aor = "user2@localhost", password = "x"},
    sip_serv_cache:put_abonent(Ab),
    ?assertEqual(true, sip_serv_cache:delete_abonent("user2@localhost")),
    ?assertEqual({error, not_found},
                 sip_serv_cache:get_abonent("user2@localhost")).

%%--------------------------------------------------------------------
%% Registration
%%--------------------------------------------------------------------
registration_put_get_delete_test() ->
    setup(),
    Now = erlang:system_time(second),
    Reg = #registration{
        aor = "user1@localhost",
        contact = "sip:user1@127.0.0.1",
        expires_time = Now + 3600,
        registered_time = Now
    },
    ?assertEqual(true, sip_serv_cache:put_registration(Reg)),
    {ok, List1} = sip_serv_cache:get_registrations("user1@localhost"),
    ?assertEqual(1, length(List1)),

    ?assertEqual(ok, sip_serv_cache:delete_registration(
                        "user1@localhost", "sip:user1@127.0.0.1")),
    {ok, List2} = sip_serv_cache:get_registrations("user1@localhost"),
    ?assertEqual(0, length(List2)).

%%--------------------------------------------------------------------
%% Subscription
%%--------------------------------------------------------------------
subscription_put_get_test() ->
    setup(),
    Now = erlang:system_time(second),
    Sub = #erlsubscription{
        id = <<"sub1">>,
        aor = "user1@localhost",
        subscriber = "user2@localhost",
        dialog_id = <<"dialog1">>,
        expires_time = Now + 3600,
        subscribed_time = Now
    },
    ?assertEqual(true, sip_serv_cache:put_subscription(Sub)),
    {ok, List} = sip_serv_cache:get_subscriptions("user1@localhost"),
    ?assertEqual(1, length(List)).

%%--------------------------------------------------------------------
%% Stats / counts
%%--------------------------------------------------------------------
stats_and_counts_test() ->
    setup(),
    Now = erlang:system_time(second),
    Reg = #registration{
        aor = "u@localhost",
        contact = "c",
        expires_time = Now + 100,
        registered_time = Now
    },
    sip_serv_cache:put_registration(Reg),

    Stats = sip_serv_cache:stats(),
    ?assert(is_map(Stats)),
    ?assert(maps:get(registrations, Stats) >= 1),

    {RegCnt, SubCnt} = sip_serv_cache:get_active_counts(),
    ?assert(RegCnt >= 1),
    ?assert(is_integer(SubCnt)).