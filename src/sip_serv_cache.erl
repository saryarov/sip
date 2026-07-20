-module(sip_serv_cache).

-include("sip_serv_records.hrl").

-behaviour(gen_server).

-export([
    start_link/0
]).

-export([
    put_abonent/1,
    get_abonent/1,
    delete_abonent/1,

    put_registration/1,
    get_registrations/1,
    delete_registration/2,
    delete_registration_object/1,

    put_subscription/1,
    get_subscriptions/1,
    delete_subscription/1,

    put_publication/1,
    get_publications/1,
    delete_publication/2,
    delete_publication_object/1

]).

-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3
]).

-export([
    get_all/1,
    stats/0,
    show/0,
    show/1,
    restore_cache/0,
    get_active_counts/0,
    get_active_stats/0
]).

%%--------------------------------------------------------------------
%% @doc
%% Запускает процесс ETS-кэша как gen_server.
%% @return `{ok, Pid}` при успешном запуске;
%%         `{error, Reason}` в случае ошибки.
%% @end
%%--------------------------------------------------------------------
-spec start_link() ->
    {ok, pid()} | {error, term()}.

start_link() ->
    gen_server:start_link(
        {local, ?MODULE},
        ?MODULE,
        [],
        []
    ).

%--------------------------------------------------------------------
%% @private
%% @doc
%% Инициализирует ETS-таблицы кэша при старте gen_server.
%% @return `{ok, #{}}`.
%% @end
%%--------------------------------------------------------------------
-spec init([]) ->
    {ok, #{}}.

init([]) ->
    ets:new(abonent_cache, [
        named_table,
        public,
        set,
        {keypos, #abonent.aor}
    ]),

    ets:new(registration_cache, [
        named_table,
        public,
        bag,
        {keypos, #registration.aor}
    ]),

    ets:new(subscription_cache, [
        named_table,
        public,
        set,
        {keypos, #erlsubscription.id}
    ]),

    ets:new(publication_cache, [
        named_table,
        public,
        bag,
        {keypos, #publication.aor}
    ]),

    {ok, #{}}.

%%--------------------------------------------------------------------
%% @doc
%% Сохраняет абонента в ETS-кэш.
%% @param Abonent запись `#abonent{}`.
%% @return `true`.
%% @end
%%--------------------------------------------------------------------
-spec put_abonent(#abonent{}) ->
    true.
put_abonent(Abonent) ->
    ets:insert(
        abonent_cache,
        Abonent
    ).

%%--------------------------------------------------------------------
%% @doc
%% Получает абонента из ETS-кэша по AOR.
%% @param Aor адрес записи абонента.
%% @return `{ok, #abonent{}}` если найден;
%%         `{error, not_found}` если не найден.
%% @end
%%--------------------------------------------------------------------
-spec get_abonent(string()) ->
    {ok, #abonent{}} |
    {error, not_found}.
get_abonent(Aor) ->
    case ets:lookup(
        abonent_cache,
        Aor
    ) of
        [Abonent] ->
            {ok, Abonent};

        [] ->
            {error, not_found}
    end.

%%--------------------------------------------------------------------
%% @doc
%% Удаляет абонента из ETS-кэша по AOR.
%% @param Aor адрес записи абонента.
%% @return `true`.
%% @end
%%--------------------------------------------------------------------
-spec delete_abonent(string()) ->
    true.
delete_abonent(Aor) ->
    ets:delete(
        abonent_cache,
        Aor
    ).

%%--------------------------------------------------------------------
%% @doc
%% Сохраняет регистрацию в ETS-кэш.
%% @param Registration запись `#registration{}`.
%% @return `true`.
%% @end
%%--------------------------------------------------------------------
-spec put_registration(#registration{}) ->
    true.
put_registration(Registration) ->
    ets:insert(
        registration_cache,
        Registration
    ).

%%--------------------------------------------------------------------
%% @doc
%% Получает все регистрации абонента из кэша по AOR.
%% @param Aor адрес записи абонента.
%% @return `{ok, [#registration{}]}` — список может быть пустым.
%% @end
%%--------------------------------------------------------------------
-spec get_registrations(string()) ->
    {ok, [#registration{}]}.
get_registrations(Aor) ->
    Registrations =
        ets:lookup(
            registration_cache,
            Aor
        ),
    {ok, Registrations}.

%%--------------------------------------------------------------------
%% @doc
%% Удаляет регистрацию абонента по AOR и контакту.
%% @param Aor адрес записи абонента.
%% @param Contact контакт регистрации.
%% @return `ok`.
%% @end
%%--------------------------------------------------------------------
-spec delete_registration(string(), string()) -> ok.
delete_registration(Aor, Contact) ->
    case ets:lookup(registration_cache, Aor) of
        [] ->
            ok;
        Registrations ->
            lists:foreach(
                fun(Registration) ->
                    case Registration#registration.contact =:= Contact of
                        true ->
                            ets:delete_object(
                                registration_cache,
                                Registration
                            );
                        false ->
                            ok
                    end
                end,
                Registrations
            ),
            ok
    end.

%%--------------------------------------------------------------------
%% @doc
%% Удаление конкретного объекта регистрации из ETS-кэша.
%% В отличие от delete_registration/2 удаляет запись по полному
%% содержимому объекта.
%% @param Registration запись #registration{}.
%% @return true.
%% @end
%%--------------------------------------------------------------------
-spec delete_registration_object(#registration{}) ->
    true.
delete_registration_object(Registration) ->
    ets:delete_object(
        registration_cache,
        Registration
    ).

%%--------------------------------------------------------------------
%% @doc
%% Сохраняет подписку в ETS-кэш.
%% @param Subscription запись `#erlsubscription{}`.
%% @return `true`.
%% @end
%%--------------------------------------------------------------------
-spec put_subscription(#erlsubscription{}) ->
    true.
put_subscription(Subscription) ->
    ets:insert(
        subscription_cache,
        Subscription
    ).

%%--------------------------------------------------------------------
%% @doc
%% Получает все подписки абонента из кэша по AOR.
%% @param Aor адрес записи абонента.
%% @return `{ok, [#erlsubscription{}]}` — список может быть пустым.
%% @end
%%--------------------------------------------------------------------
-spec get_subscriptions(string()) ->
    {ok, [#erlsubscription{}]}.
get_subscriptions(Aor) ->
    Subscriptions =
        ets:foldl(
            fun(Subscription, Acc) ->
                case Subscription#erlsubscription.aor =:= Aor of
                    true ->
                        [Subscription | Acc];
                    false ->
                        Acc
                end
            end,
            [],
            subscription_cache
        ),
    {ok, lists:reverse(Subscriptions)}.

%%--------------------------------------------------------------------
%% @doc
%% Удаляет подписку из кэша по идентификатору.
%% @param Id уникальный идентификатор подписки (binary()).
%% @return `true`.
%% @end
%%--------------------------------------------------------------------
-spec delete_subscription(binary()) ->
    true.
delete_subscription(Id) ->
    ets:delete(
        subscription_cache,
        Id
    ).

%%--------------------------------------------------------------------
%% @doc
%% Сохраняет публикацию в ETS-кэш.
%% @param Publication запись `#publication{}`.
%% @return `true`.
%% @end
%%--------------------------------------------------------------------
-spec put_publication(#publication{}) ->
    true.
put_publication(Publication) ->
    ets:insert(
        publication_cache,
        Publication
    ).

%%--------------------------------------------------------------------
%% @doc
%% Получает все публикации абонента из кэша по AOR.
%% @param Aor адрес записи абонента.
%% @return `{ok, [#publication{}]}` — список может быть пустым.
%% @end
%%--------------------------------------------------------------------
-spec get_publications(string()) ->
    {ok, [#publication{}]}.
get_publications(Aor) ->
    Publications =
        ets:lookup(
            publication_cache,
            Aor
        ),
    {ok, Publications}.

%%--------------------------------------------------------------------
%% @doc
%% Удаляет публикацию по AOR и тегу.
%% @param Aor адрес записи абонента.
%% @param Tag уникальный тег публикации.
%% @return `ok`.
%% @end
%%--------------------------------------------------------------------
-spec delete_publication(string(), string()) ->
    ok.
delete_publication(Aor, Tag) ->
    case ets:lookup(
        publication_cache,
        Aor
    ) of
        [] ->
            ok;

        Publications ->
            lists:foreach(
                fun(Publication) ->
                    case Publication#publication.tag =:= Tag of
                        true ->
                            ets:delete_object(
                                publication_cache,
                                Publication
                            );
                        false ->
                            ok
                    end
                end,
                Publications
            ),
            ok
    end.

%%--------------------------------------------------------------------
%% @doc
%% Удаление конкретного объекта публикации из ETS-кэша.
%% Удаляет запись по полному содержимому объекта.
%% @param Publication запись #publication{}.
%% @return true.
%% @end
%%--------------------------------------------------------------------
-spec delete_publication_object(#publication{}) ->
    true.
delete_publication_object(Publication) ->
    ets:delete_object(
        publication_cache,
        Publication
    ).

%%--------------------------------------------------------------------
%% @doc
%% Возвращает количество объектов в каждой таблице ETS-кэша.
%% @return Карта со статистикой кэша.
%% @end
%%--------------------------------------------------------------------
-spec stats() -> #{
    abonents := non_neg_integer(),
    registrations := non_neg_integer(),
    subscriptions := non_neg_integer(),
    publications := non_neg_integer()
}.
stats() ->
    #{
        abonents => ets:info(abonent_cache, size),
        registrations => ets:info(registration_cache, size),
        subscriptions => ets:info(subscription_cache, size),
        publications => ets:info(publication_cache, size)
    }.

%%--------------------------------------------------------------------
%% @doc
%% Возвращает все объекты выбранного типа из ETS-кэша.
%% @param Type тип данных: abonents, registrations,
%%             subscriptions или publications.
%% @return {ok, Objects} либо {error, invalid_type}.
%% @end
%%--------------------------------------------------------------------
-spec get_all(
    abonents |
    registrations |
    subscriptions |
    publications
) ->
    {ok, [tuple()]} |
    {error, invalid_type}.
get_all(abonents) ->
    {ok, ets:tab2list(abonent_cache)};

get_all(registrations) ->
    {ok, ets:tab2list(registration_cache)};

get_all(subscriptions) ->
    {ok, ets:tab2list(subscription_cache)};

get_all(publications) ->
    {ok, ets:tab2list(publication_cache)};

get_all(_) ->
    {error, invalid_type}.

%%--------------------------------------------------------------------
%% @doc
%% Выводит краткую статистику и содержимое всех таблиц ETS-кэша.
%% Предназначена для диагностики и демонстрации работы кэша.
%% @return ok.
%% @end
%%--------------------------------------------------------------------
-spec show() -> ok.
show() ->
    io:format("~n========== SIP SERV CACHE ==========~n", []),
    io:format("Abonents:      ~p~n", [ets:info(abonent_cache, size)]),
    io:format("Registrations: ~p~n", [ets:info(registration_cache, size)]),
    io:format("Subscriptions: ~p~n", [ets:info(subscription_cache, size)]),
    io:format("Publications:  ~p~n", [ets:info(publication_cache, size)]),
    io:format("====================================~n", []),

    show(abonents),
    show(registrations),
    show(subscriptions),
    show(publications),

    ok.

%%--------------------------------------------------------------------
%% @doc
%% Выводит содержимое выбранной таблицы ETS-кэша.
%% @param Type тип таблицы.
%% @return ok либо {error, invalid_type}.
%% @end
%%--------------------------------------------------------------------
-spec show(
    abonents |
    registrations |
    subscriptions |
    publications
) ->
    ok | {error, invalid_type}.
show(Type) ->
    case get_all(Type) of
        {ok, Objects} ->
            io:format(
                "~n--- ~s (~p objects) ---~n",
                [string:uppercase(atom_to_list(Type)), length(Objects)]
            ),

            lists:foreach(
                fun(Object) ->
                    io:format("~p~n", [Object])
                end,
                Objects
            ),

            ok;

        {error, invalid_type} ->
            {error, invalid_type}
    end.

%%--------------------------------------------------------------------
%% @doc
%% Выполняет поиск данных в ETS-кэше.
%%
%% Для abonent ключом является AOR.
%% Для registration и publication поиск выполняется по AOR.
%% Для subscription ключом является идентификатор подписки.
%%
%% @param Type тип объекта.
%% @param Key ключ поиска.
%% @return {ok, ObjectOrObjects}, если данные найдены;
%%         {error, not_found}, если данные отсутствуют;
%%         {error, invalid_type}, если передан неизвестный тип.
%% @end
%%--------------------------------------------------------------------
-spec find(
    abonent |
    registration |
    subscription |
    publication,
    term()
) ->
    {ok, tuple() | [tuple()]} |
    {error, not_found | invalid_type}.
find(abonent, Aor) ->
    get_abonent(Aor);

find(registration, Aor) ->
    case get_registrations(Aor) of
        {ok, []} ->
            {error, not_found};

        {ok, Registrations} ->
            {ok, Registrations}
    end;

find(subscription, Id) ->
    case ets:lookup(subscription_cache, Id) of
        [Subscription] ->
            {ok, Subscription};

        [] ->
            {error, not_found}
    end;

find(publication, Aor) ->
    case get_publications(Aor) of
        {ok, []} ->
            {error, not_found};

        {ok, Publications} ->
            {ok, Publications}
    end;

find(_, _) ->
    {error, invalid_type}.

-spec get_active_stats() ->
    {[#registration{}], [#erlsubscription{}]}.

get_active_stats() ->
    {
        ets:tab2list(registration_cache),
        ets:tab2list(subscription_cache)
    }.

-spec get_active_counts() ->
    {non_neg_integer(), non_neg_integer()}.

get_active_counts() ->
    {
        ets:info(registration_cache, size),
        ets:info(subscription_cache, size)
    }.

%%--------------------------------------------------------------------
%% @doc
%% Восстанавливает содержимое ETS-кэша из таблиц Mnesia.
%%
%% Сначала в одной транзакции получает все записи из постоянного
%% хранилища. После успешного чтения очищает ETS-таблицы и заполняет
%% их актуальными данными из Mnesia.
%%
%% @return ok при успешном восстановлении;
%%         {error, Reason} при ошибке чтения Mnesia.
%% @end
%%--------------------------------------------------------------------
-spec restore_cache() ->
    ok | {error, term()}.

restore_cache() ->
    ReadTable =
        fun(Table) ->
            mnesia:foldl(
                fun(Record, Acc) ->
                    [Record | Acc]
                end,
                [],
                Table
            )
        end,

    Transaction =
        fun() ->
            {
                ReadTable(abonent),
                ReadTable(registration),
                ReadTable(erlsubscription),
                ReadTable(publication)
            }
        end,

    case mnesia:transaction(Transaction) of
        {atomic, {
            Abonents,
            Registrations,
            Subscriptions,
            Publications
        }} ->
            clear_cache(),

            lists:foreach(
                fun put_abonent/1,
                Abonents
            ),

            lists:foreach(
                fun put_registration/1,
                Registrations
            ),

            lists:foreach(
                fun put_subscription/1,
                Subscriptions
            ),

            lists:foreach(
                fun put_publication/1,
                Publications
            ),

            ok;

        {aborted, Reason} ->
                error_logger:error_msg(
        "[~p:~p] Failed to restore ETS cache from Mnesia: ~p~n",
        [?MODULE, ?LINE, Reason]
    ),
            {error, Reason}
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Удаляет все объекты из таблиц ETS-кэша.
%% Сами ETS-таблицы при этом продолжают существовать.
%% @return true.
%% @end
%%--------------------------------------------------------------------
-spec clear_cache() ->
    true.

clear_cache() ->
    ets:delete_all_objects(abonent_cache),
    ets:delete_all_objects(registration_cache),
    ets:delete_all_objects(subscription_cache),
    ets:delete_all_objects(publication_cache).

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.