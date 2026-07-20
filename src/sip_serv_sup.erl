%% @doc
%% Супервизор верхнего уровня для приложения SIP-сервера.
%% Запускает и контролирует все дочерние процессы.
%% Реализует поведение supervisor, со стратегией one_for_one.
%% @end

-module(sip_serv_sup).

-behaviour(supervisor).

-export([start_link/0]).

-export([init/1]).

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
            id => sip_serv_cleanup,
            start => {sip_serv_cleanup, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [sip_serv_cleanup]
        },
        #{
            id => sip_serv_cache,
            start => {sip_serv_cache, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [sip_serv_cache]
        },
        nksip:get_sup_spec(sip_serv_handler, #{
            sip_local_host => "localhost",
            plugins => [nksip_registrar],
            sip_listen => "sip:all:5060",
            sip_events => [<<"presence">>]
        })
    ],
    {ok, {SupFlags, ChildSpecs}}.