%%%-------------------------------------------------------------------
%% @doc
%% Модуль приложения sip_serv.
%%
%% При запуске:
%% - создаёт схему базы данных (если её ещё нет);
%% - запускает Mnesia;
%% - создаёт таблицы базы данных;
%% - ожидает загрузки таблиц;
%% - загружает абонентов из конфигурационного файла;
%% - запускает супервизор приложения.
%% @end
%%%-------------------------------------------------------------------

-module(sip_serv_app).

-behaviour(application).

-export([start/2, stop/1]).

-include("sip_serv_records.hrl").

%%--------------------------------------------------------------------
%% @doc
%% Запускает приложение.
%% @param StartType тип запуска приложения.
%% @param StartArgs аргументы запуска приложения.
%% @return {ok, Pid}, если приложение успешно запущено;
%%         {error, Reason} в случае ошибки.
%% @end
%%--------------------------------------------------------------------
-spec start(application:start_type(), term()) ->
    {ok, pid()} | {error, term()}.
start(_StartType, _StartArgs) ->

    Dispatch = cowboy_router:compile([
        {'_', [

            %% API
            {"/api/stats",           sip_stats_handler, []},
            {"/api/users",           sip_user_handler,  []},
            {"/api/users/:aor", sip_user_handler,  []},

            %% Мониторинг / логи
            {"/api/monitor/log",      sip_log_handler, []},
            {"/api/monitor/log/full", sip_log_handler, []}
        ]}
    ]),

    {ok, _} = cowboy:start_clear(rest_listener,
        [{port, 8080}],
        #{env => #{dispatch => Dispatch}}
    ),

    io:format("~n[INFO] REST API started on http://localhost:8080~n"),

    %% Останавливаем Mnesia, если она уже была запущена
    mnesia:stop(),

    %% Создаём схему только при первом запуске
    case mnesia:create_schema([node()]) of
        ok ->
            start_mnesia();
        {error, {_, {already_exists, _}}} ->
            start_mnesia();
        {error, {already_exists, _}} ->
            start_mnesia();
        {error, SchemaReason} ->
            error_logger:error_msg(
                "Create schema failed: ~p~n",
                [SchemaReason]
            ),
            {error, SchemaReason}
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Запускает Mnesia, создаёт таблицы, загружает конфигурацию
%% и запускает супервизор приложения.
%% @return {ok, Pid}, если Mnesia успешно запущена и приложение
%%         инициализировано; {error, Reason} при ошибке запуска.
%% @end
%%--------------------------------------------------------------------
-spec start_mnesia() ->
    {ok, pid()} | {error, term()}.
start_mnesia() ->
    case mnesia:start() of
        ok ->
            start_application();
        {error, {already_started, _}} ->
            start_application();
        {error, StartReason} ->
            error_logger:error_msg(
                "Mnesia start failed: ~p~n",
                [StartReason]
            ),
            {error, StartReason}
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Выполняет инициализацию базы данных, ожидает готовности таблиц,
%% загружает абонентов и запускает супервизор приложения.
%% @return {ok, Pid}, если приложение успешно инициализировано;
%%         {error, Reason} при ошибке ожидания таблиц
%%         или запуска супервизора.
%% @end
%%--------------------------------------------------------------------
-spec start_application() ->
    {ok, pid()} | {error, term()}.
start_application() ->

    %% Создаём таблицы
    sip_serv_db:init_db(),

    %% Ожидаем готовности таблиц Mnesia
    case mnesia:wait_for_tables(
        [abonent, registration, erlsubscription, publication],
        30000
    ) of
        ok ->
            %% Запускаем супервизор, чтобы создались ETS-таблицы
            case sip_serv_sup:start_link() of
                {ok, Pid} ->
                    case sip_serv_cache:restore_cache() of
                        ok ->
                            ok;

                        {error, RestoreReason} ->
                            error_logger:error_msg(
                                "Cache restore failed: ~p~n",
                                [RestoreReason]
                            )
                    end,

                    load_abonents(),
                    {ok, Pid};

                {error, SupErr} ->
                    mnesia:stop(),
                    {error, SupErr}
            end;

        {timeout, BadTables} ->
            mnesia:stop(),
            {error, {timeout, BadTables}};

        {error, WaitReason} ->
            mnesia:stop(),
            {error, WaitReason}
    end.
%%--------------------------------------------------------------------
%% @doc
%% Загружает абонентов из конфигурационного файла в базу данных.
%% @return ok после завершения загрузки всех корректных записей.
%% @end
%%--------------------------------------------------------------------
-spec load_abonents() -> ok.
load_abonents() ->
    Abonents = sip_serv_conf:get_abonents(),

    lists:foreach(
        fun(AbonentMap) ->
            Aor = maps:get(aor, AbonentMap, undefined),
            Password = maps:get(password, AbonentMap, undefined),
            Domain = maps:get(domain, AbonentMap, undefined),

            case Aor =:= undefined orelse
                 Password =:= undefined orelse
                 Domain =:= undefined of
                true ->
                    error_logger:warning_msg(
                        "Skipping invalid abonent entry: ~p~n",
                        [AbonentMap]
                    );
                false ->
                    sip_serv_db:add_abonent(
                        #abonent{
                            aor = Aor,
                            password = Password,
                            domain = Domain,
                            create_time = erlang:system_time(second)
                        }
                    )
            end
        end,
        Abonents
    ),

    ok.

%%--------------------------------------------------------------------
%% @doc
%% Завершает работу приложения.
%% @param State состояние приложения, передаваемое OTP при завершении.
%% @return ok.
%% @end
%%--------------------------------------------------------------------
-spec stop(term()) -> ok.
stop(_State) ->
    mnesia:stop(),
    ok.