%%%-------------------------------------------------------------------
%%% @doc callback-модуль NkSIP
%%%-------------------------------------------------------------------
-module(sip_serv_handler).

-export([
    sip_get_user_pass/4,
    sip_authorize/3,
    sip_route/5,
    sip_register/2,
    sip_registrar_store/2,
    sip_subscribe/2,
    sip_publish/2,
    sip_event_compositor_store/2
]).

-include("sip_serv_records.hrl").
-include_lib("nkserver/include/nkserver_module.hrl").

-define(REALM, <<"localhost">>).


%%====================================================================
%% Основные колбэки NkSIP
%%====================================================================

%%--------------------------------------------------------------------
%% @doc
%% Возвращает пароль пользователя по его имени.
%% Используется для Digest-аутентификации.
%%
%% @param User Имя пользователя
%% @param _Realm Realm (не используется)
%% @param _Req Запрос (не используется)
%% @param _Call Вызов (не используется)
%% @return Пароль в бинарном виде или пустой бинар
%% @end
%%--------------------------------------------------------------------
-spec sip_get_user_pass(binary(), term(), nksip:request(), nksip:call()) -> binary().
sip_get_user_pass(User, _Realm, _Req, _Call) ->
    error_logger:info_msg("[~p:~p] Looking up password for user ~p",
                          [?MODULE, ?LINE, User]),
    AorStr = binary_to_list(<<User/binary, "@", ?REALM/binary>>),
    case sip_serv_db:get_abonent(AorStr) of
        {ok, Password} when is_binary(Password) -> Password;
        {ok, Password} when is_list(Password)   -> list_to_binary(Password);
        {ok, {ok, Password}}                    -> list_to_binary(Password);
        {ok, Other} ->
            error_logger:warning_msg("[~p:~p] Unexpected password format for ~s: ~p",
                                     [?MODULE, ?LINE, AorStr, Other]),
            <<>>;
        {error, Reason} ->
            error_logger:warning_msg("[~p:~p] Password not found for ~s: ~p",
                                     [?MODULE, ?LINE, AorStr, Reason]),
            <<>>
    end.

%%--------------------------------------------------------------------
%% @doc
%% Авторизация входящих запросов.
%% Возвращает ok или {proxy_authenticate, Realm}.
%%
%% @param AuthList Список аутентификаций
%% @param Req Входящий запрос
%% @param _Call Вызов
%% @return ok | {proxy_authenticate, binary()}
%% @end
%%--------------------------------------------------------------------
-spec sip_authorize(list(), nksip:request(), nksip:call()) ->
    ok | {proxy_authenticate, binary()}.
sip_authorize(AuthList, Req, _Call) ->
    error_logger:info_msg("[~p:~p] Authorization started. AuthList: ~p",
                          [?MODULE, ?LINE, AuthList]),
    Method = nksip_request:method(Req),
    error_logger:info_msg("[~p:~p] Incoming method: ~p",
                          [?MODULE, ?LINE, Method]),

    IsDialog   = lists:member(dialog, AuthList),
    IsRegister = lists:member(register, AuthList),

    error_logger:info_msg("[~p:~p] IsDialog=~p, IsRegister=~p",
                          [?MODULE, ?LINE, IsDialog, IsRegister]),

    case IsDialog orelse IsRegister of
        true ->
            error_logger:info_msg("[~p:~p] Authorization skipped (dialog or register)",
                                  [?MODULE, ?LINE]),
            ok;
        false ->
            case lists:keyfind({digest, ?REALM}, 1, AuthList) of
                {_, true} -> ok;
                _         ->
                    error_logger:info_msg("[~p:~p] Digest authentication required for realm ~p",
                                          [?MODULE, ?LINE, ?REALM]),
                    {proxy_authenticate, ?REALM}
            end
    end.

%%--------------------------------------------------------------------
%% @doc
%% Определяет, обрабатывать ли запрос локально или проксировать.
%%
%% @param _Scheme Схема (sip/sips)
%% @param _User Имя пользователя
%% @param _Domain Домен
%% @param Req Запрос
%% @param _Call Вызов
%% @return process | proxy
%% @end
%%--------------------------------------------------------------------
-spec sip_route(atom(), binary(), binary(), nksip:request(), nksip:call()) ->
    process | proxy.
sip_route(_Scheme, <<>>, <<"localhost">>, _Req, _Call) -> process;

sip_route(_Scheme, _User, _Domain, Req, _Call) ->
    case nksip_request:is_local_ruri(Req) of
        true  -> process;
        false -> proxy
    end.

%%--------------------------------------------------------------------
%% @doc
%% Обработка REGISTER. Различает регистрацию и де-регистрацию.
%% При де-регистрации NOTIFY не отправляется.
%%
%% @param Req REGISTER запрос
%% @param _Call Вызов
%% @return {reply, nksip:sipreply()}
%% @end
%%--------------------------------------------------------------------
sip_register(Req, _Call) ->
    {ok, [{from_user, FromUser}, {from_domain, FromDomain}, {expires, Expires}]} =
        nksip_request:get_metas([from_user, from_domain, expires], Req),

    AorStr = binary_to_list(<<FromUser/binary, "@", FromDomain/binary>>),

    %% Нормализуем Expires
    ExpiresVal = case Expires of
        undefined -> 3600;                    % по умолчанию считаем регистрацией
        E when is_integer(E) -> E;
        _ -> 0
    end,

    error_logger:info_msg("[~p:~p] REGISTER received from ~s, Expires=~p",
                          [?MODULE, ?LINE, AorStr, ExpiresVal]),

    case ExpiresVal of
        0 ->
            %% Дерегистрация
            error_logger:info_msg("[~p:~p] User ~s is de-registering. NOTIFY will not be sent.",
                                  [?MODULE, ?LINE, AorStr]),
            {reply, nksip_registrar:request(Req)};

        _ ->
            %% Регистрация
            error_logger:info_msg("[~p:~p] User ~s successfully registered (Expires=~p)",
                                  [?MODULE, ?LINE, AorStr, ExpiresVal]),
            {reply, nksip_registrar:request(Req)}
    end.
%%====================================================================
%% Registrar Store
%%====================================================================
%%--------------------------------------------------------------------
%% @doc
%% Колбэк хранилища регистраций (используется плагином nksip_registrar).
%%
%% @param _AppId Идентификатор сервиса
%% @param Op Операция ({get, AOR}, {put, ...}, {del, AOR}, del_all)
%% @return [RegContact] | ok | not_found
%% @end
%%--------------------------------------------------------------------
-spec sip_registrar_store(nksip:srv_id(), term()) ->
    [term()] | ok | not_found.
sip_registrar_store(_AppId, {get, AOR}) ->
    AorStr = aor_to_string(AOR),
    Now = erlang:system_time(second),

    error_logger:info_msg("[~p:~p] Registrar store GET for AOR: ~s",
                          [?MODULE, ?LINE, AorStr]),

    case sip_serv_db:get_registrations(AorStr) of
        {ok, Regs} ->
            Active = [R || R <- Regs, R#registration.expires_time > Now],

            error_logger:info_msg("[~p:~p] Found ~p active registrations for ~s (total: ~p)",
                                  [?MODULE, ?LINE, length(Active), AorStr, length(Regs)]),

            [binary_to_term(list_to_binary(R#registration.contact)) || R <- Active];
        _ ->
            error_logger:info_msg("[~p:~p] No registrations found for ~s",
                                  [?MODULE, ?LINE, AorStr]),
            []
    end;

sip_registrar_store(_AppId, {put, AOR, Contacts, TTL}) ->
    AorStr = aor_to_string(AOR),

    error_logger:info_msg("[~p:~p] Registrar store PUT for AOR: ~s, Contacts: ~p, TTL: ~p",
                          [?MODULE, ?LINE, AorStr, length(Contacts), TTL]),

    sip_serv_db:delete_all_registrations(AorStr),
    Now = erlang:system_time(second),

    lists:foreach(fun(RegContact) ->
        Serialized = binary_to_list(term_to_binary(RegContact)),
        Rec = #registration{
            aor             = AorStr,
            contact         = Serialized,
            expires_time    = Now + TTL,
            registered_time = Now
        },
        sip_serv_db:add_registration(Rec)
    end, Contacts),
    error_logger:info_msg("[~p:~p] PUT completed for ~s",
                          [?MODULE, ?LINE, AorStr]),
    ok;

sip_registrar_store(_AppId, {del, AOR}) ->
    AorStr = aor_to_string(AOR),
    error_logger:info_msg("[~p:~p] Registrar store DELETE for AOR: ~s",
                          [?MODULE, ?LINE, AorStr]),
    sip_serv_db:delete_all_registrations(aor_to_string(AOR)),
    ok;

sip_registrar_store(_AppId, del_all) ->
    error_logger:info_msg("[~p:~p] Registrar store DELETE ALL",
                          [?MODULE, ?LINE]),
    case sip_serv_db:get_all_registrations() of
        {ok, All} ->
            lists:foreach(fun(R) ->
                sip_serv_db:delete_registration(R#registration.aor, R#registration.contact)
            end, All);
        _ -> ok
    end.

%%--------------------------------------------------------------------
%% @doc
%% Преобразует AOR (Address of Record) в строку вида "user@domain".
%%
%% @param AOR Кортеж AOR в формате {Scheme, User, Domain}
%% @return Строка в формате "user@domain"
%% @end
%%--------------------------------------------------------------------
-spec aor_to_string(nksip:aor()) -> string().
aor_to_string({_Scheme, User, Domain}) ->
    binary_to_list(<<User/binary, "@", Domain/binary>>).

%%====================================================================
%% Presence (SUBSCRIBE / PUBLISH)
%%====================================================================

%%--------------------------------------------------------------------
%% @doc
%% Обработка SUBSCRIBE на presence.
%% Сохраняет подписку и отправляет первый NOTIFY.
%%
%% @param Req SUBSCRIBE запрос
%% @param _Call Вызов
%% @return {reply, nksip:sipreply()}
%% @end
%%--------------------------------------------------------------------
-spec sip_subscribe(nksip:request(), nksip:call()) -> {reply, nksip:sipreply()}.
sip_subscribe(Req, _Call) ->
    error_logger:info_msg("[~p:~p] SUBSCRIBE request received",
                          [?MODULE, ?LINE]),
    case nksip_request:get_metas([event, expires, ruri, from], Req) of
        {ok, [{event, {<<"presence">>, _}},
              {expires, Expires0},
              {ruri, Ruri},
              {from, From}]} ->

            Expires = case Expires0 of
                undefined -> 3600;
                E when is_integer(E), E > 0 -> E;
                _ -> 0
            end,

            Presentity = case is_tuple(Ruri) of true -> element(3, Ruri); false -> <<"unknown">> end,
            Domain     = case is_tuple(Ruri) of true -> element(5, Ruri); false -> <<"localhost">> end,
            Subscriber = case is_tuple(From) of true -> element(3, From); false -> <<"unknown">> end,

            AorStr      = binary_to_list(<<Presentity/binary, "@", Domain/binary>>),
            SubscriberStr = binary_to_list(<<Subscriber/binary, "@", Domain/binary>>),

            Now = erlang:system_time(second),

            error_logger:info_msg("[~p:~p] Presence SUBSCRIBE: Subscriber=~s, Presentity=~s, Expires=~p",
                                  [?MODULE, ?LINE, SubscriberStr, AorStr, Expires]),

            case Expires of
                0 ->
                    error_logger:info_msg("[~p:~p] Subscription terminated for ~s (Expires=0)",
                                          [?MODULE, ?LINE, SubscriberStr]),
                    sip_serv_db:delete_subscriptions(SubscriberStr),
                    {reply, ok};

                _ ->
                    %% === Получаем настоящий handle ===
                    case nksip_subscription:get_handle(Req) of
                        {ok, SubsHandle} ->
                            Subscription = #erlsubscription{
                                id              = list_to_binary(ref_to_list(make_ref())),
                                aor             = AorStr,
                                subscriber      = SubscriberStr,
                                dialog_id       = SubsHandle,        % ← сохраняем настоящий handle
                                expires_time    = Now + Expires,
                                subscribed_time = Now
                            },

                            case sip_serv_db:add_subscription(Subscription) of
                                ok ->
                                    error_logger:info_msg("[~p:~p] Subscription saved: ~s watches ~s (Expires=~p)",
                                                          [?MODULE, ?LINE, SubscriberStr, AorStr, Expires]),

                                    %% Первый NOTIFY
                                    spawn(fun() ->
                                        timer:sleep(100),
                                        try
                                            Result = nksip_uac:notify(SubsHandle, [
                                                {subscription_state, active},
                                                {expires, Expires},
                                                {content_type, <<"application/pidf+xml">>},
                                                {body, presence_body_open()}
                                            ]),
                                            error_logger:info_msg("[~p:~p] First NOTIFY sent to ~s, result: ~p",
                                                                  [?MODULE, ?LINE, SubscriberStr, Result])
                                        catch
                                            _:Err -> error_logger:error_msg("[~p:~p] Failed to send first NOTIFY to ~s: ~p",
                                                                       [?MODULE, ?LINE, SubscriberStr, Err])
                                        end
                                    end),

                                    {reply, {ok, [
                                        {expires, Expires},
                                        {contact, "sip:sip-server@localhost:5060"}
                                    ]}};

                                {error, Reason} ->
                                    error_logger:error_msg("[~p:~p] DB error while saving subscription: ~p",
                                                           [?MODULE, ?LINE, Reason]),
                                    {reply, {internal_error, "Cannot save subscription"}}
                            end;

                        {error, Reason} ->
                            error_logger:error_msg("[~p:~p] Failed to get subscription handle: ~p",
                                                   [?MODULE, ?LINE, Reason]),
                            {reply, {internal_error, "Cannot get subscription handle"}}
                    end
            end;

        Other ->
            error_logger:warning_msg("[~p:~p] Unsupported SUBSCRIBE event: ~p",
                                     [?MODULE, ?LINE, Other]),
            {reply, {not_acceptable, "Only presence supported"}}
    end.

%%--------------------------------------------------------------------
%% @doc
%% Обработка PUBLISH. Отправляет NOTIFY только зарегистрированным пользователям.
%%
%% @param Req PUBLISH запрос
%% @param _Call Вызов
%% @return {reply, nksip:sipreply()}
%% @end
%%--------------------------------------------------------------------
-spec sip_publish(nksip:request(), nksip:call()) -> {reply, nksip:sipreply()}.
sip_publish(Req, _Call) ->
    error_logger:info_msg("[~p:~p] PUBLISH request received",
                          [?MODULE, ?LINE]),
    Reply = nksip_event_compositor:request(Req),

    case Reply of
        {ok, _} ->
            case nksip_request:get_metas([from, body], Req) of
                {ok, [{from, From}, {body, Body}]} ->
                    Presentity = case is_tuple(From) of true -> element(3, From); false -> <<"unknown">> end,
                    Domain     = case is_tuple(From) of true -> element(5, From); false -> <<"localhost">> end,
                    AorStr = binary_to_list(<<Presentity/binary, "@", Domain/binary>>),

                    error_logger:info_msg("[~p:~p] PUBLISH for ~s, body size: ~p bytes",
                                          [?MODULE, ?LINE, AorStr, byte_size(Body)]),

                    %% === ПРОВЕРКА: отправляем NOTIFY только если пользователь зарегистрирован ===
                    case is_user_registered(AorStr) of
                        true ->
                            %% Сохраняем последнее тело
                            FinalBody = case is_binary(Body) andalso byte_size(Body) > 0 of
                                true  -> Body;
                                false -> presence_body_open()
                            end,
                            sip_serv_db:add_publication(#publication{
                                aor = AorStr,
                                tag = "presence",
                                data = FinalBody,
                                expires_time = erlang:system_time(second) + 3600,
                                published_time = erlang:system_time(second)
                            }),

                            %% Находим подписчиков и отправляем NOTIFY
                            case sip_serv_db:get_subscriptions(AorStr) of
                                {ok, Subscriptions} ->
                                    ActiveSubs = lists:filter(
                                        fun(#erlsubscription{expires_time = Exp}) ->
                                            Exp > erlang:system_time(second)
                                        end, Subscriptions),

                                    error_logger:info_msg("[~p:~p] User ~s is registered. Found ~p active watchers",
                                                          [?MODULE, ?LINE, AorStr, length(ActiveSubs)]),

                                    lists:foreach(
                                        fun(Sub) ->
                                            spawn(fun() -> send_notify_to_watcher(Sub, AorStr) end)
                                        end, ActiveSubs);
                                _ -> error_logger:info_msg("[~p:~p] No active subscriptions for ~s",
                                                          [?MODULE, ?LINE, AorStr])
                            end;

                        false ->
                            error_logger:info_msg("[~p:~p] User ~s is NOT registered. NOTIFY not sent.",
                                                  [?MODULE, ?LINE, AorStr])
                    end;

                _ ->
                    error_logger:warning_msg("[~p:~p] Failed to parse PUBLISH request",
                                             [?MODULE, ?LINE])
            end,
            {reply, Reply};
        Other ->
            {reply, Other}
    end.

%%====================================================================
%% Вспомогательные функции
%%====================================================================
%%--------------------------------------------------------------------
%% @doc
%% Возвращает тело PIDF со статусом <basic>open</basic>.
%% Используется как fallback, когда нет актуальной публикации.
%%
%% @return Бинарное тело presence-документа
%% @end
%%--------------------------------------------------------------------
-spec presence_body_open() -> binary().
presence_body_open() ->
    <<"<presence xmlns=\"urn:ietf:params:xml:ns:pidf\" entity=\"pres:user1@localhost\">"
      "<tuple id=\"t1\"><status><basic>open</basic></status></tuple>"
      "</presence>">>.
%%--------------------------------------------------------------------
%% @doc
%% Отправляет NOTIFY одному подписчику.
%% Берёт тело из последнего PUBLISH или использует заглушку.
%%
%% @param Sub Запись подписки (#erlsubscription{})
%% @param Presentity AOR публикующего пользователя (например, "user1@localhost")
%% @end
%%--------------------------------------------------------------------
-spec send_notify_to_watcher(#erlsubscription{}, string()) -> ok.
send_notify_to_watcher(#erlsubscription{} = Sub, Presentity) ->
    ExpiresLeft = max(0, Sub#erlsubscription.expires_time - erlang:system_time(second)),

    error_logger:info_msg("[~p:~p] Preparing NOTIFY for watcher ~s (presentity: ~s, expires left: ~p)",
                          [?MODULE, ?LINE, Sub#erlsubscription.subscriber, Presentity, ExpiresLeft]),

    %% Берём реальное тело из последнего PUBLISH
    Body = case sip_serv_db:get_publication(Presentity, "presence") of
        {ok, #publication{data = Data}} ->
            if is_binary(Data) -> Data; true -> list_to_binary(io_lib:format("~p", [Data])) end;
        _ ->
            error_logger:info_msg("[~p:~p] No publication found for ~s, using default body",
                                    [?MODULE, ?LINE, Presentity]),
            presence_body_open()
    end,

    Handle = Sub#erlsubscription.dialog_id,

    try
        Result = nksip_uac:notify(Handle, [
            {subscription_state, active},
            {expires, ExpiresLeft},
            {content_type, <<"application/pidf+xml">>},
            {body, Body}
        ]),
        error_logger:info_msg("[~p:~p] NOTIFY sent to ~s -> ~p",
                              [?MODULE, ?LINE, Sub#erlsubscription.subscriber, Result])
    catch
        _:invalid_dialog ->
            error_logger:warning_msg("[~p:~p] Cannot send NOTIFY to ~s: invalid handle",
                                     [?MODULE, ?LINE, Sub#erlsubscription.subscriber]);
        _:Err ->
            error_logger:error_msg("[~p:~p] Failed to send NOTIFY to ~s: ~p",
                                   [?MODULE, ?LINE, Sub#erlsubscription.subscriber, Err])
    end.

%%====================================================================
%% Event Store
%%====================================================================

%%--------------------------------------------------------------------
%% @doc
%% Колбэк хранилища для плагина nksip_event_compositor.
%%
%% @param _AppId Идентификатор сервиса
%% @param Op Операция хранилища
%% @return ok | not_found | {ok, term()}
%% @end
%%--------------------------------------------------------------------
-spec sip_event_compositor_store(nksip:srv_id(), term()) ->
    ok | not_found | {ok, term()}.
sip_event_compositor_store(_AppId, Op) ->
    error_logger:info_msg("[~p:~p] Event compositor store operation: ~p",
                          [?MODULE, ?LINE, Op]),

    case Op of
        %% Получить публикацию
        {get, AOR, Tag} ->
            AorStr = aor_to_string(AOR),
            TagStr = binary_to_list(Tag),
            error_logger:info_msg("[~p:~p] GET publication: AOR=~s, Tag=~s",
                                  [?MODULE, ?LINE, AorStr, TagStr]),
            case sip_serv_db:get_publication(AorStr, TagStr) of
                {ok, Pub} -> {ok, Pub};
                _         -> not_found
            end;

        %% Сохранить публикацию
        {put, AOR, Tag, RegPublish, TTL} ->
            AorStr = aor_to_string(AOR),
            TagStr = binary_to_list(Tag),
            Now = erlang:system_time(second),

            error_logger:info_msg("[~p:~p] PUT publication: AOR=~s, Tag=~s, TTL=~p",
                                  [?MODULE, ?LINE, AorStr, TagStr, TTL]),

            Pub = #publication{
                aor             = AorStr,
                tag             = TagStr,
                data            = RegPublish,
                expires_time    = Now + TTL,
                published_time  = Now
            },
            sip_serv_db:add_publication(Pub),
            ok;

        %% Удалить конкретную публикацию
        {del, AOR, Tag} ->
            AorStr = aor_to_string(AOR),
            TagStr = binary_to_list(Tag),

            error_logger:info_msg("[~p:~p] DELETE publication: AOR=~s, Tag=~s",
                                  [?MODULE, ?LINE, AorStr, TagStr]),

            sip_serv_db:delete_publication(AorStr, TagStr),
            ok;

        %% Удалить все
        del_all ->
            error_logger:info_msg("[~p:~p] DELETE ALL publications",
                                  [?MODULE, ?LINE]),
            sip_serv_db:delete_all_publications(),
            ok;

        _ ->
            ok
    end.

%%====================================================================
%% Вспомогательные функции
%%====================================================================

%%--------------------------------------------------------------------
%% @doc
%% Проверяет, есть ли у пользователя активные регистрации на текущий момент.
%%
%% @param AorStr Адрес записи пользователя (например, "user1@localhost")
%% @return true, если есть хотя бы одна активная регистрация, иначе false
%% @end
%%--------------------------------------------------------------------
-spec is_user_registered(string()) -> boolean().
is_user_registered(AorStr) ->
    error_logger:info_msg("[~p:~p] Checking if user is registered: ~s",
                          [?MODULE, ?LINE, AorStr]),

    case sip_serv_db:get_registrations(AorStr) of
        {ok, Regs} ->
            Now = erlang:system_time(second),
            Active = lists:any(fun(R) -> R#registration.expires_time > Now end, Regs),
            error_logger:info_msg("[~p:~p] User ~s registration check: ~p (found ~p regs)",
                                  [?MODULE, ?LINE, AorStr, Active, length(Regs)]),
            Active;
        _ ->
            error_logger:info_msg("[~p:~p] User ~s has no registrations",
                                  [?MODULE, ?LINE, AorStr]),
            false
    end.