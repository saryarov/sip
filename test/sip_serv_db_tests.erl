-module(sip_serv_db_tests).
-include_lib("eunit/include/eunit.hrl").
-include("sip_serv_records.hrl").

%%--------------------------------------------------------------------
%% setup / teardown
%%--------------------------------------------------------------------
setup() ->
    %% Mnesia
    application:load(mnesia),
    mnesia:stop(),
    ok = mnesia:delete_schema([node()]),
    ok = mnesia:create_schema([node()]),
    {ok, _} = application:ensure_all_started(mnesia),

    %% Cache
    case whereis(sip_serv_cache) of
        undefined ->
            {ok, _} = sip_serv_cache:start_link();
        _ ->
            ok
    end,

    %% Tables
    ok = sip_serv_db:init_db(),
    ok.

%%--------------------------------------------------------------------
%% Abonent
%%--------------------------------------------------------------------
abonent_add_get_delete_test() ->
    setup(),
    Ab = #abonent{aor = "user1@localhost", password = "secret"},
    ?assertEqual(ok, sip_serv_db:add_abonent(Ab)),

    ?assertEqual({ok, "secret"}, sip_serv_db:get_abonent("user1@localhost")),

    ?assertEqual(ok, sip_serv_db:delete_abonent("user1@localhost")),
    ?assertEqual({error, not_found}, sip_serv_db:get_abonent("user1@localhost")).

%%--------------------------------------------------------------------
%% Registration
%%--------------------------------------------------------------------
registration_add_get_delete_test() ->
    setup(),
    Now = erlang:system_time(second),
    Reg = #registration{
        aor = "user1@localhost",
        contact = "sip:user1@127.0.0.1",
        expires_time = Now + 3600,
        registered_time = Now
    },
    ?assertEqual(ok, sip_serv_db:add_registration(Reg)),

    {ok, List} = sip_serv_db:get_registrations("user1@localhost"),
    ?assertEqual(1, length(List)),

    ?assertEqual(ok, sip_serv_db:delete_registration(
                        "user1@localhost", "sip:user1@127.0.0.1")),
    {ok, List2} = sip_serv_db:get_registrations("user1@localhost"),
    ?assertEqual(0, length(List2)).

%%--------------------------------------------------------------------
%% Subscription
%%--------------------------------------------------------------------
subscription_add_get_test() ->
    setup(),
    Now = erlang:system_time(second),
    Sub = #erlsubscription{
        id = <<"sub_db_1">>,
        aor = "user1@localhost",
        subscriber = "user2@localhost",
        dialog_id = <<"dlg1">>,
        expires_time = Now + 3600,
        subscribed_time = Now
    },
    ?assertEqual(ok, sip_serv_db:add_subscription(Sub)),

    {ok, List} = sip_serv_db:get_subscriptions("user1@localhost"),
    ?assertEqual(1, length(List)),

    ?assertEqual(ok, sip_serv_db:delete_subscription(<<"sub_db_1">>)).

%%--------------------------------------------------------------------
%% Publication
%%--------------------------------------------------------------------
publication_add_get_test() ->
    setup(),
    Now = erlang:system_time(second),
    Pub = #publication{
        aor = "user1@localhost",
        tag = "presence",
        data = <<"<presence/>">>,
        expires_time = Now + 3600,
        published_time = Now
    },
    ?assertEqual(ok, sip_serv_db:add_publication(Pub)),

    ?assertMatch({ok, #publication{tag = "presence"}},
                 sip_serv_db:get_publication("user1@localhost", "presence")),

    ?assertEqual(ok, sip_serv_db:delete_publication("user1@localhost", "presence")),
    ?assertEqual({error, not_found},
                 sip_serv_db:get_publication("user1@localhost", "presence")).