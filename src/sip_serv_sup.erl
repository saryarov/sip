%% @doc
%% Супервизор верхнего уровня для приложения SIP-сервера.
%% Запускает и контролирует все дочерние процессы.
%% Реализует поведение supervisor, со стратегией one_for_one.
%% @end

-module(sip_serv_sup).

-behaviour(supervisor).

-export([start_link/0]).

-export([init/1]).

-export([start_nksip/0, start_cache/0, start_cowboy/0, stop_nksip/0, stop_cache/0, stop_cowboy/0]).

-define(SERVER, ?MODULE).

%% doc
%% Запуск супервизора и связывание его с вызывающим процессом.
%% Точка входа для супервизора верхнего уровня.
%% @return Возвращает {ok, Pid} при успешном запуске супервизора
%% (Pid - идентификатор процесса, возвращает {error, Reason} при ошибке запуска.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%% doc
%% Функция, вызываемая при старте супервизора для инициализации его конфигурации
%% и списка дочерних процессов.
%% @return {ok, {SupFlags, ChildSpecs}}, где SupFlags - способ обработки падения
%% прилежения и его перезапуска, ChildSpecs - спецификация наблюдаемых дочерних процессов.
-spec init([]) -> {ok, {supervisor:sup_flags(), [supervisor:child_spec()]}}.
init([]) ->
    SupFlags = #{
        strategy => one_for_one,
        intensity => 5,
        period => 10
    },
    ChildSpecs = [
        #{
            id => sip_serv_master,
            start => {sip_serv_master, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [sip_serv_master]
        },
        #{
            id => sip_serv_cleanup,
            start => {sip_serv_cleanup, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [sip_serv_cleanup]
        }
    ],
    {ok, {SupFlags, ChildSpecs}}.

%% doc
%% Функция запуска дочернего процесса NkSIP
%% @return ok при запуске или если NkSIP уже запущен, {error, Reason} в случае ошибки
-spec start_nksip() -> ok | {error, term()}.
start_nksip() ->
    ChildSpec = nksip:get_sup_spec(sip_serv_handler,
    #{
        sip_local_host => "127.0.0.100",
        plugins => [nksip_registrar],
        sip_listen => "sip:all:5060",
        sip_events => [<<"presence">>]
    }),
    case supervisor:start_child(?MODULE, ChildSpec#{id => nksip_child}) of
        {ok, _} ->
            ok;
        {error, {already_started, _}} ->
            ok;
        {error, Reason} ->
            {error, Reason}
    end.

%% doc
%% Функция остановки и удаления дочернего процесса NkSIP
%% @return Возвращает ok , если процесс успешно завершен и удален,
%% или {error, Reason} при ошибке
-spec stop_nksip() -> {ok, [supervisor:child_spec()]} | ok | {error, term()}.
stop_nksip() ->
    case supervisor:terminate_child(?MODULE, nksip_child) of
        ok ->
            supervisor:delete_child(?MODULE, nksip_child);
        {error, not_found} ->
            ok;
        {error, Reason} ->
            {error, Reason}
    end.

%% doc
%% Функция запуска дочернего процесса cache
%% @return ok при запуске или если cache уже запущен, {error, Reason} в случае ошибки
-spec start_cache() -> ok | {error, term()}.
start_cache() ->
    CacheSpecs = #{
        id => sip_serv_cache,
        start => {sip_serv_cache, start_link, []},
        restart => permanent,
        shutdown => 5000,
        type => worker,
        modules => [sip_serv_cache]
    },
    case supervisor:start_child(?MODULE, CacheSpecs) of
        {ok, _} ->
            ok;
        {error, {already_started, _}} ->
            ok;
        {error, Reason} ->
            {error, Reason}
    end.

%% doc
%% Функция остановки и удаления дочернего процесса cache
%% @return Возвращает ok , если процесс успешно завершен и удален,
%% или {error, Reason} при ошибке
-spec stop_cache() -> {ok, [supervisor:child_spec()]} | ok | {error, term()}.
stop_cache() ->
    case supervisor:terminate_child(?MODULE, sip_serv_cache) of
        ok ->
            supervisor:delete_child(?MODULE, sip_serv_cache);
        {error, not_found} ->
            ok;
        {error, Reason} ->
            {error, Reason}
    end.

%% doc
%% Функция запуска дочернего процесса cowboy
%% @return ok при запуске или если cowboy уже запущен, {error, Reason} в случае ошибки
-spec start_cowboy() -> ok | {error, term()}.
start_cowboy() ->
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
    case cowboy:start_clear(rest_listener, [{port, 8080}], #{env => #{dispatch => Dispatch}}) of
        {ok, _} ->
            error_logger:info_msg("~n[~p:~p] REST API started on http://localhost:8080~n", [?MODULE, ?LINE]),
            ok;
        {error, not_found} ->
            ok;
        {error, Reason} ->
            {error, Reason}
    end.

%% doc
%% Функция остановки и удаления дочернего процесса cowboy
%% @return Возвращает ok , если процесс успешно завершен и удален,
%% или {error, Reason} при ошибке
-spec stop_cowboy() -> {ok, [supervisor:child_spec()]} | ok | {error, term()}.
stop_cowboy() ->
    cowboy:stop_listener(rest_listener).