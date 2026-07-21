%%%-------------------------------------------------------------------
%% @doc
%% Модуль работы с базой данных Mnesia.
%% Предоставляет API для хранения, получения и удаления данных
%% об абонентах, регистрациях и подписках.
%% @end
%%%-------------------------------------------------------------------

-module(sip_serv_db).

-include("sip_serv_records.hrl").

%%====================================================================
%% API
%%====================================================================

-export([
    init_db/0,

    add_abonent/1,
    get_abonent/1,
    delete_abonent/1,

    add_registration/1,
    delete_registration/2,
    delete_all_registrations/1,
    get_registrations/1,
    get_all_registrations/0,

    add_subscription/1,
    delete_subscription/1,
    get_subscriptions/1,

    add_publication/1,
    delete_publication/2,
    delete_all_publications/0,
    delete_all_publications/1,
    get_publication/2,
    get_publications/1,
    get_all_publications/0,

    delete_expired/0
]).

%%====================================================================
%% API implementation
%%====================================================================

%%--------------------------------------------------------------------
%% @doc
%% Инициализация базы данных Mnesia.
%% Создаёт таблицы abonent, registration, publication и subscription,
%% если они ещё не существуют.
%% @return ok при успешной инициализации;
%%         {error, Reason} в случае ошибки.
%% @end
%%--------------------------------------------------------------------
-spec init_db() -> ok | {error, term()}.
init_db() ->
    Tables = [
        {abonent, record_info(fields, abonent), set},
        {registration, record_info(fields, registration), bag},
        {erlsubscription, record_info(fields, erlsubscription), set},
        {publication, record_info(fields, publication), bag}
    ],
    lists:foreach(fun({Table, Attributes, TableType}) ->
        case create_table(Table, Attributes, TableType) of
            ok ->
                ok;
            {error, Reason} ->
                logger:error("Error create/copy table ~p: ~p (Module ~p, Line ~p)~n", [Table, Reason, ?MODULE, ?LINE]),
                {error, Reason}
        end
    end, Tables),
    ok.

%%--------------------------------------------------------------------
%% @doc
%% Внутренняя функция для создания таблицы Mnesia.
%% @param Table имя создаваемой таблицы.
%% @param Attributes список атрибутов записи.
%% @return ok при успешном создании;
%%         {error, Reason} в случае ошибки.
%% @end
%%--------------------------------------------------------------------
-spec create_table(atom(), [atom()], atom()) -> ok | {error, term()}.
create_table(Table, Attributes, TableType) ->
    case mnesia:create_table(Table, [
        {attributes, Attributes},
        {disc_copies, [node()]},
        {type, TableType}
    ]) of
        {atomic, ok} ->
            ok;
        {aborted, {already_exists, Table}} ->
            case lists:member(node(), mnesia:table_info(Table, disc_copies)) of
                true ->
                    ok;
                false ->
                    logger:info("Copy the ~p table to my disc (Module ~p, Line ~p)", [Table, ?MODULE, ?LINE]),
                    case mnesia:add_table_copy(Table, node(), disc_copies) of
                        {atomic, ok} ->
                            ok;
                        {abortet, Reason} ->
                            {error, Reason}
                    end
                end;
        {aborted, Reason} ->
            {error, Reason}
    end.

%%--------------------------------------------------------------------
%% @doc
%% Добавление нового абонента в базу данных.
%% @param Abonent запись #abonent{} для сохранения.
%% @return ok при успешном добавлении;
%%         {error, Reason} в случае ошибки.
%% @end
%%--------------------------------------------------------------------
-spec add_abonent(#abonent{}) ->
    ok | {error, term()}.
add_abonent(Abonent) ->
    Fun = fun() ->
        mnesia:write(Abonent)
    end,
    case mnesia:transaction(Fun) of
        {atomic, ok} ->
            sip_serv_cache:put_abonent(Abonent),
            ok;
        {aborted, Reason} ->
                        error_logger:error_msg(
                "[~p:~p] Failed to add abonent: ~p~n",
                [?MODULE, ?LINE, Reason]
            ),
            {error, Reason}
    end.

%%--------------------------------------------------------------------
%% @doc
%% Получение пароля абонента по его AOR.
%% Сначала выполняет поиск в ETS-кэше. Если запись отсутствует,
%% получает её из Mnesia и сохраняет в кэш.
%% @param Aor адрес записи (Address of Record) абонента.
%% @return {ok, Password}, если абонент найден;
%%         {error, not_found}, если запись отсутствует;
%%         {error, Reason} при ошибке Mnesia.
%% @end
%%--------------------------------------------------------------------
-spec get_abonent(string()) ->
    {ok, string()} | {error, not_found | term()}.
get_abonent(Aor) ->
    case sip_serv_cache:get_abonent(Aor) of
        {ok, Abonent} ->
            {ok, Abonent#abonent.password};

        {error, not_found} ->
            get_abonent_from_db(Aor)
    end.
%%--------------------------------------------------------------------
%% @private
%% @doc
%% Получение абонента непосредственно из Mnesia.
%% При успешном чтении сохраняет запись в ETS-кэш.
%% @end
%%--------------------------------------------------------------------
-spec get_abonent_from_db(string()) ->
    {ok, string()} | {error, not_found | term()}.
get_abonent_from_db(Aor) ->
    Fun = fun() ->
        mnesia:read(abonent, Aor)
    end,

    case mnesia:transaction(Fun) of
        {atomic, [Abonent]} ->
            sip_serv_cache:put_abonent(Abonent),
            {ok, Abonent#abonent.password};

        {atomic, []} ->
            {error, not_found};

        {aborted, Reason} ->
             error_logger:error_msg(
                "[~p:~p] Failed to get abonent ~p from Mnesia: ~p~n",
                [?MODULE, ?LINE, Aor, Reason]
            ),
            {error, Reason}
    end.
%%--------------------------------------------------------------------
%% @doc
%% Удаление абонента из Mnesia и ETS-кэша по его AOR.
%% @param Aor адрес записи (Address of Record) абонента.
%% @return ok при успешном удалении;
%%         {error, Reason} в случае ошибки Mnesia.
%% @end
%%--------------------------------------------------------------------
-spec delete_abonent(string()) ->
    ok | {error, term()}.
delete_abonent(Aor) ->
    Fun = fun() ->
        mnesia:delete({abonent, Aor})
    end,

    case mnesia:transaction(Fun) of
        {atomic, ok} ->
            sip_serv_cache:delete_abonent(Aor),
            ok;
        {aborted, Reason} ->
            error_logger:error_msg(
                "[~p:~p] Failed to delete abonent ~p from Mnesia: ~p~n",
                [?MODULE, ?LINE, Aor, Reason]
            ),
            {error, Reason}
    end.
%%--------------------------------------------------------------------
%% @doc
%% Добавление новой регистрации абонента.
%% @param Registration запись #registration{}.
%% @return ok при успешном добавлении;
%%         {error, Reason} в случае ошибки.
%% @end
%%--------------------------------------------------------------------
-spec add_registration(#registration{}) ->
    ok | {error, term()}.
add_registration(Registration) ->
    Fun = fun() ->
        mnesia:write(Registration)
    end,
    case mnesia:transaction(Fun) of
        {atomic, ok} ->
            sip_serv_cache:put_registration(Registration),
            ok;
        {aborted, Reason} ->
             error_logger:error_msg(
            "[~p:~p] Failed to add registration for ~p: ~p~n",
            [?MODULE, ?LINE, Registration#registration.aor, Reason]
        ),
            {error, Reason}
    end.

%%--------------------------------------------------------------------
%% @doc
%% Удаление конкретной регистрации абонента из Mnesia и ETS-кэша
%% по AOR и контакту.
%% @param Aor адрес записи (Address of Record) абонента.
%% @param Contact контактный SIP URI регистрации.
%% @return ok при успешном удалении;
%%         {error, Reason} в случае ошибки Mnesia.
%% @end
%%--------------------------------------------------------------------
-spec delete_registration(string(), string()) ->
    ok | {error, term()}.
delete_registration(Aor, Contact) ->
    Fun = fun() ->
        Registrations =
            mnesia:match_object(#registration{
                aor = Aor,
                contact = Contact,
                expires_time = '_',
                registered_time = '_'
            }),

        lists:foreach(
            fun(Registration) ->
                mnesia:delete_object(Registration)
            end,
            Registrations
        )
    end,

    case mnesia:transaction(Fun) of
        {atomic, ok} ->
            sip_serv_cache:delete_registration(Aor, Contact),
            ok;

        {aborted, Reason} ->
             error_logger:error_msg(
            "[~p:~p] Failed to delete registration (~p, ~p): ~p~n",
            [?MODULE, ?LINE, Aor, Contact, Reason]
        ),
            {error, Reason}
    end.

%%--------------------------------------------------------------------
%% @doc
%% Удаление всех регистраций абонента из Mnesia и ETS-кэша.
%% @param Aor адрес записи (Address of Record) абонента.
%% @return ok при успешном удалении;
%%         {error, Reason} в случае ошибки Mnesia.
%% @end
%%--------------------------------------------------------------------
-spec delete_all_registrations(string()) ->
    ok | {error, term()}.
delete_all_registrations(Aor) ->
    Fun = fun() ->
        Registrations =
            mnesia:match_object(#registration{
                aor = Aor,
                contact = '_',
                expires_time = '_',
                registered_time = '_'
            }),

        lists:foreach(
            fun(Registration) ->
                mnesia:delete_object(Registration)
            end,
            Registrations
        ),

        Registrations
    end,

    case mnesia:transaction(Fun) of
        {atomic, Registrations} ->
            lists:foreach(
                fun(Registration) ->
                    sip_serv_cache:delete_registration(
                        Registration#registration.aor,
                        Registration#registration.contact
                    )
                end,
                Registrations
            ),
            ok;

        {aborted, Reason} ->
            error_logger:error_msg(
            "[~p:~p] Failed to delete all registrations for ~p: ~p~n",
            [?MODULE, ?LINE, Aor, Reason]
        ),
            {error, Reason}
    end.
%%--------------------------------------------------------------------
%% @doc
%% Получение всех регистраций абонента по его AOR.
%% Сначала выполняет поиск в ETS-кэше. Если кэш пуст,
%% получает регистрации из Mnesia и сохраняет их в ETS.
%% @param Aor адрес записи (Address of Record) абонента.
%% @return {ok, Registrations} при успешном получении;
%%         {error, Reason} в случае ошибки Mnesia.
%% @end
%%--------------------------------------------------------------------
-spec get_registrations(string()) ->
    {ok, [#registration{}]} | {error, term()}.
get_registrations(Aor) ->
    case sip_serv_cache:get_registrations(Aor) of
        {ok, [_ | _] = Registrations} ->
            {ok, Registrations};

        {ok, []} ->
            get_registrations_from_db(Aor)
    end.

    %%--------------------------------------------------------------------
%% @private
%% @doc
%% Получение регистраций непосредственно из Mnesia.
%% Найденные записи сохраняются в ETS-кэш.
%% @end
%%--------------------------------------------------------------------
-spec get_registrations_from_db(string()) ->
    {ok, [#registration{}]} | {error, term()}.
get_registrations_from_db(Aor) ->
    Fun = fun() ->
        mnesia:match_object(#registration{
            aor = Aor,
            contact = '_',
            expires_time = '_',
            registered_time = '_'
        })
    end,

    case mnesia:transaction(Fun) of
        {atomic, Registrations} ->
            lists:foreach(
                fun(Registration) ->
                    sip_serv_cache:put_registration(Registration)
                end,
                Registrations
            ),
            {ok, Registrations};

        {aborted, Reason} ->
             error_logger:error_msg(
                "[~p:~p] Failed to get registrations for ~p from Mnesia: ~p~n",
                [?MODULE, ?LINE, Aor, Reason]
            ),
            {error, Reason}
    end.
%%--------------------------------------------------------------------
%% @doc
%% Получение всех регистраций всех абонентов в системе.
%% @return {ok, Registrations} при успешном получении;
%%         {error, Reason} в случае ошибки.
%% @end
%%--------------------------------------------------------------------
-spec get_all_registrations() ->
    {ok, [#registration{}]} | {error, term()}.
get_all_registrations() ->
    Fun = fun() ->
        mnesia:match_object(#registration{
            aor = '_',
            contact = '_',
            expires_time = '_',
            registered_time = '_'
        })
    end,
    case mnesia:transaction(Fun) of
        {atomic, Registrations} ->
            {ok, Registrations};
        {aborted, Reason} ->
            error_logger:error_msg(
                "[~p:~p] Failed to get all registrations from Mnesia: ~p~n",
                [?MODULE, ?LINE, Reason]
            ),
            {error, Reason}
    end.

%%--------------------------------------------------------------------
%% @doc
%% Добавление новой подписки на событие в Mnesia и ETS-кэш.
%% @param Subscription запись #erlsubscription{}.
%% @return ok при успешном добавлении;
%%         {error, Reason} в случае ошибки.
%% @end
%%--------------------------------------------------------------------
-spec add_subscription(#erlsubscription{}) ->
    ok | {error, term()}.
add_subscription(Subscription) ->
    Fun = fun() ->
        mnesia:write(Subscription)
    end,
    case mnesia:transaction(Fun) of
        {atomic, ok} ->
            sip_serv_cache:put_subscription(Subscription),
            ok;
        {aborted, Reason} ->
             error_logger:error_msg(
                "[~p:~p] Failed to add subscription ~p: ~p~n",
                [?MODULE, ?LINE, Subscription#erlsubscription.id, Reason]
            ),
            {error, Reason}
    end.

%%--------------------------------------------------------------------
%% @doc
%% Удаление подписки из Mnesia и ETS-кэша по её идентификатору.
%% @param Id идентификатор подписки.
%% @return ok при успешном удалении;
%%         {error, Reason} в случае ошибки.
%% @end
%%--------------------------------------------------------------------
-spec delete_subscription(binary()) ->
    ok | {error, term()}.
delete_subscription(Id) ->
    Fun = fun() ->
        mnesia:delete({erlsubscription, Id})
    end,
    case mnesia:transaction(Fun) of
        {atomic, ok} ->
            sip_serv_cache:delete_subscription(Id),
            ok;
        {aborted, Reason} ->
             error_logger:error_msg(
                "[~p:~p] Failed to delete subscription ~p: ~p~n",
                [?MODULE, ?LINE, Id, Reason]
            ),
            {error, Reason}
    end.

%%--------------------------------------------------------------------
%% @doc
%% Получение всех подписок абонента по его AOR.
%% Сначала выполняет поиск в ETS-кэше. Если кэш пуст,
%% получает подписки из Mnesia и сохраняет их в ETS.
%% @param Aor адрес записи (Address of Record) абонента.
%% @return {ok, Subscriptions} при успешном получении;
%%         {error, Reason} в случае ошибки Mnesia.
%% @end
%%--------------------------------------------------------------------
-spec get_subscriptions(string()) ->
    {ok, [#erlsubscription{}]} | {error, term()}.
get_subscriptions(Aor) ->
    case sip_serv_cache:get_subscriptions(Aor) of
        {ok, [_ | _] = Subscriptions} ->
            {ok, Subscriptions};

        {ok, []} ->
            get_subscriptions_from_db(Aor)
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Получение подписок непосредственно из Mnesia.
%% Найденные записи сохраняются в ETS-кэш.
%% @end
%%--------------------------------------------------------------------
-spec get_subscriptions_from_db(string()) ->
    {ok, [#erlsubscription{}]} | {error, term()}.
get_subscriptions_from_db(Aor) ->
    Fun = fun() ->
        mnesia:match_object(#erlsubscription{
            id = '_',
            aor = Aor,
            subscriber = '_',
            dialog_id = '_',
            expires_time = '_',
            subscribed_time = '_'
        })
    end,

    case mnesia:transaction(Fun) of
        {atomic, Subscriptions} ->
            lists:foreach(
                fun(Subscription) ->
                    sip_serv_cache:put_subscription(Subscription)
                end,
                Subscriptions
            ),
            {ok, Subscriptions};

        {aborted, Reason} ->
             error_logger:error_msg(
                "[~p:~p] Failed to get subscriptions for ~p from Mnesia: ~p~n",
                [?MODULE, ?LINE, Aor, Reason]
            ),
            {error, Reason}
    end.

%%--------------------------------------------------------------------
%% @doc
%% Добавление новой публикации состояния в Mnesia и ETS-кэш.
%% @param Publication запись #publication{}.
%% @return ok при успешном добавлении;
%%         {error, Reason} в случае ошибки.
%% @end
%%--------------------------------------------------------------------
-spec add_publication(#publication{}) ->
    ok | {error, term()}.
add_publication(Publication) ->
    Fun = fun() ->
        mnesia:write(Publication)
    end,
    case mnesia:transaction(Fun) of
        {atomic, ok} ->
            sip_serv_cache:put_publication(Publication),
            ok;
        {aborted, Reason} ->
             error_logger:error_msg(
                "[~p:~p] Failed to add publication (~p, ~p): ~p~n",
                [?MODULE, ?LINE,
                 Publication#publication.aor,
                 Publication#publication.tag,
                 Reason]
            ),
            {error, Reason}
    end.
%%--------------------------------------------------------------------
%% @doc
%% Удаление всех публикаций из Mnesia и ETS-кэша.
%% @return ok при успешном удалении;
%%         {error, Reason} в случае ошибки Mnesia.
%% @end
%%--------------------------------------------------------------------
-spec delete_all_publications() ->
    ok | {error, term()}.
delete_all_publications() ->
    Fun = fun() ->
        Publications =
            mnesia:match_object(#publication{
                aor = '_',
                tag = '_',
                data = '_',
                expires_time = '_',
                published_time = '_'
            }),

        lists:foreach(
            fun(Publication) ->
                mnesia:delete_object(Publication)
            end,
            Publications
        ),

        Publications
    end,

    case mnesia:transaction(Fun) of
        {atomic, Publications} ->
            lists:foreach(
                fun(Publication) ->
                    sip_serv_cache:delete_publication(
                        Publication#publication.aor,
                        Publication#publication.tag
                    )
                end,
                Publications
            ),
            ok;
        {aborted, Reason} ->
             error_logger:error_msg(
                "[~p:~p] Failed to delete all publications from Mnesia: ~p~n",
                [?MODULE, ?LINE, Reason]
            ),
            {error, Reason}
    end.
%%--------------------------------------------------------------------
%% @doc
%% Удаление конкретной публикации из Mnesia и ETS-кэша
%% по AOR и тегу.
%% @param Aor адрес записи абонента.
%% @param Tag тег публикации.
%% @return ok при успешном удалении;
%%         {error, Reason} в случае ошибки Mnesia.
%% @end
%%--------------------------------------------------------------------
-spec delete_publication(string(), string()) ->
    ok | {error, term()}.
delete_publication(Aor, Tag) ->
    Fun = fun() ->
        Publications =
            mnesia:match_object(#publication{
                aor = Aor,
                tag = Tag,
                data = '_',
                expires_time = '_',
                published_time = '_'
            }),

        lists:foreach(
            fun(Publication) ->
                mnesia:delete_object(Publication)
            end,
            Publications
        )
    end,

    case mnesia:transaction(Fun) of
        {atomic, ok} ->
            sip_serv_cache:delete_publication(Aor, Tag),
            ok;
        {aborted, Reason} ->
             error_logger:error_msg(
                "[~p:~p] Failed to delete publication (~p, ~p): ~p~n",
                [?MODULE, ?LINE, Aor, Tag, Reason]
            ),
            {error, Reason}
    end.

%%--------------------------------------------------------------------
%% @doc
%% Удаление всех публикаций абонента из Mnesia и ETS-кэша.
%% @param Aor адрес записи абонента.
%% @return ok при успешном удалении;
%%         {error, Reason} в случае ошибки Mnesia.
%% @end
%%--------------------------------------------------------------------
-spec delete_all_publications(string()) ->
    ok | {error, term()}.
delete_all_publications(Aor) ->
    Fun = fun() ->
        Publications =
            mnesia:match_object(#publication{
                aor = Aor,
                tag = '_',
                data = '_',
                expires_time = '_',
                published_time = '_'
            }),

        lists:foreach(
            fun(Publication) ->
                mnesia:delete_object(Publication)
            end,
            Publications
        ),

        Publications
    end,

    case mnesia:transaction(Fun) of
        {atomic, Publications} ->
            lists:foreach(
                fun(Publication) ->
                    sip_serv_cache:delete_publication(
                        Publication#publication.aor,
                        Publication#publication.tag
                    )
                end,
                Publications
            ),
            ok;

        {aborted, Reason} ->
            error_logger:error_msg(
                "[~p:~p] Failed to delete all publications for ~p: ~p~n",
                [?MODULE, ?LINE, Aor, Reason]
            ),
            {error, Reason}
    end.

%%--------------------------------------------------------------------
%% @doc
%% Получение всех публикаций абонента по его AOR.
%% Сначала выполняет поиск в ETS-кэше. Если кэш пуст,
%% получает публикации из Mnesia и сохраняет их в ETS.
%% @param Aor адрес записи (Address of Record) абонента.
%% @return {ok, Publications} при успешном получении;
%%         {error, Reason} в случае ошибки Mnesia.
%% @end
%%--------------------------------------------------------------------
-spec get_publications(string()) ->
    {ok, [#publication{}]} | {error, term()}.
get_publications(Aor) ->
    case sip_serv_cache:get_publications(Aor) of
        {ok, [_ | _] = Publications} ->
            {ok, Publications};

        {ok, []} ->
            get_publications_from_db(Aor)
    end.
%%--------------------------------------------------------------------
%% @private
%% @doc
%% Получение публикаций непосредственно из Mnesia.
%% Найденные записи сохраняются в ETS-кэш.
%% @end
%%--------------------------------------------------------------------
-spec get_publications_from_db(string()) ->
    {ok, [#publication{}]} | {error, term()}.
get_publications_from_db(Aor) ->
    Fun = fun() ->
        mnesia:match_object(#publication{
            aor = Aor,
            tag = '_',
            data = '_',
            expires_time = '_',
            published_time = '_'
        })
    end,

    case mnesia:transaction(Fun) of
        {atomic, Publications} ->
            lists:foreach(
                fun(Publication) ->
                    sip_serv_cache:put_publication(Publication)
                end,
                Publications
            ),
            {ok, Publications};

        {aborted, Reason} ->
            error_logger:error_msg(
                "[~p:~p] Failed to get publications for ~p from Mnesia: ~p~n",
                [?MODULE, ?LINE, Aor, Reason]
            ),
            {error, Reason}
    end.

%%--------------------------------------------------------------------
%% @doc
%% Получение конкретной публикации по AOR и тегу.
%% Сначала выполняет поиск среди публикаций в ETS-кэше.
%% При отсутствии данных в кэше загружает публикации из Mnesia.
%% @param Aor адрес записи абонента.
%% @param Tag тег публикации.
%% @return {ok, Publication}, если публикация найдена;
%%         {error, not_found}, если публикация отсутствует;
%%         {error, Reason} при ошибке Mnesia.
%% @end
%%--------------------------------------------------------------------
-spec get_publication(string(), string()) ->
    {ok, #publication{}} | {error, not_found | term()}.
get_publication(Aor, Tag) ->
    case get_publications(Aor) of
        {ok, Publications} ->
            case lists:filter(
                fun(Publication) ->
                    Publication#publication.tag =:= Tag
                end,
                Publications
            ) of
                [Publication | _] ->
                    {ok, Publication};

                [] ->
                    {error, not_found}
            end;

        {error, Reason} ->
            {error, Reason}
    end.
%%--------------------------------------------------------------------
%% @doc
%% Получение всех публикаций всех абонентов.
%% @return {ok, Publications} при успешном получении;
%%         {error, Reason} в случае ошибки.
%% @end
%%--------------------------------------------------------------------
-spec get_all_publications() ->
    {ok, [#publication{}]} | {error, term()}.
get_all_publications() ->
    Fun = fun() ->
        mnesia:match_object(#publication{
            aor = '_',
            tag = '_',
            data = '_',
            expires_time = '_',
            published_time = '_'
        })
    end,

    case mnesia:transaction(Fun) of
        {atomic, Publications} ->
            {ok, Publications};
        {aborted, Reason} ->
                error_logger:error_msg(
                    "[~p:~p] Failed to get all publications from Mnesia: ~p~n",
                    [?MODULE, ?LINE, Reason]
                ),
            {error, Reason}
    end.
%%--------------------------------------------------------------------
%% @doc
%% Удаление всех просроченных регистраций, подписок и публикаций
%% из Mnesia и ETS-кэша.
%% Сравнивает время истечения каждой записи с текущим временем.
%% @return ok при успешном удалении;
%%         {error, Reason} в случае ошибки Mnesia.
%% @end
%%--------------------------------------------------------------------
-spec delete_expired() ->
    ok | {error, term()}.
delete_expired() ->
    Now = erlang:system_time(second),

    Fun = fun() ->
        Registrations =
            mnesia:match_object(#registration{
                aor = '_',
                contact = '_',
                expires_time = '_',
                registered_time = '_'
            }),

        ExpiredRegistrations =
            lists:filter(
                fun(Registration) ->
                    Registration#registration.expires_time =< Now
                end,
                Registrations
            ),

        lists:foreach(
            fun(Registration) ->
                mnesia:delete_object(Registration)
            end,
            ExpiredRegistrations
        ),

        Subscriptions =
            mnesia:match_object(#erlsubscription{
                id = '_',
                aor = '_',
                subscriber = '_',
                dialog_id = '_',
                expires_time = '_',
                subscribed_time = '_'
            }),

        ExpiredSubscriptions =
            lists:filter(
                fun(Subscription) ->
                    Subscription#erlsubscription.expires_time =< Now
                end,
                Subscriptions
            ),

        lists:foreach(
            fun(Subscription) ->
                mnesia:delete_object(Subscription)
            end,
            ExpiredSubscriptions
        ),

        Publications =
            mnesia:match_object(#publication{
                aor = '_',
                tag = '_',
                data = '_',
                expires_time = '_',
                published_time = '_'
            }),

        ExpiredPublications =
            lists:filter(
                fun(Publication) ->
                    Publication#publication.expires_time =< Now
                end,
                Publications
            ),

        lists:foreach(
            fun(Publication) ->
                mnesia:delete_object(Publication)
            end,
            ExpiredPublications
        ),

        {
            ExpiredRegistrations,
            ExpiredSubscriptions,
            ExpiredPublications
        }
    end,

    case mnesia:transaction(Fun) of
        {atomic, {
            ExpiredRegistrations,
            ExpiredSubscriptions,
            ExpiredPublications
        }} ->
            lists:foreach(
                fun(Registration) ->
                    sip_serv_cache:delete_registration_object(
                        Registration
                    )
                end,
                ExpiredRegistrations
            ),

            lists:foreach(
                fun(Subscription) ->
                    sip_serv_cache:delete_subscription(
                        Subscription#erlsubscription.id
                    )
                end,
                ExpiredSubscriptions
            ),

            lists:foreach(
                fun(Publication) ->
                    sip_serv_cache:delete_publication_object(
                        Publication
                    )
                end,
                ExpiredPublications
            ),

            ok;

        {aborted, Reason} ->
            error_logger:error_msg(
    "[~p:~p] Failed to delete expired records from Mnesia: ~p~n",
    [?MODULE, ?LINE, Reason]
),
            {error, Reason}
    end.