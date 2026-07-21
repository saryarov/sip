%%%-------------------------------------------------------------------
%% @doc
%% Модуль приложения sip_serv.
%%
%% При запуске:
%% создаёт схему базы данных (если её ещё нет);
%% запускает Mnesia;
%% создаёт таблицы базы данных;
%% ожидает загрузки таблиц;
%% загружает абонентов из конфигурационного файла;
%% запускает супервизор приложения.
%% @end
%%%-------------------------------------------------------------------

-module(sip_serv_app).

-behaviour(application).

-export([start/2, stop/1]).

-include("sip_serv_records.hrl").

%%--------------------------------------------------------------------
%% @doc
%% Запускает приложение и Mnesia
%% @param StartType тип запуска приложения.
%% @param StartArgs аргументы запуска приложения.
%% @return {ok, Pid}, если Mnesia успешно запущена и приложение
%%         инициализировано; {error, Reason} при ошибке запуска.
%% @end
%%--------------------------------------------------------------------
-spec start(application:start_type(), term()) -> {ok, pid()} | {error, term()}.
start(_StartType, _StartArgs) ->
    ClusterNode = application:get_env(sip_serv, cluster_nodes, [node()]),
    Node = node(),

    %% Подключаемся к другим узлам
    lists:foreach(fun(N) ->
        case net_adm:ping(N) of
            pong ->
                error_logger:info_msg("~n [~p:~p] Connect to ~p~n", [?MODULE, ?LINE, N]);
            pang ->
                ok
        end
    end, ClusterNode -- [Node]),
    mnesia:stop(),

    %% Проверяем существует ли схема Mnesia
    IsSchema = case catch mnesia:table_info(schema, disc_copies) of
        [Node | _] ->
            true;
        _ ->
            false
    end,
    case IsSchema of
        true ->
            mnesia:start();
        false ->
            LiveNodes = live_nodes(ClusterNode -- [Node], 5),
            case LiveNodes of
                [] ->
                    %% Если узлов больше нет, создаем новую схему
                    error_logger:info_msg("[~p:~p] Create schema in ~p~n", [?MODULE, ?LINE, Node]),
                    mnesia:create_schema([Node]),
                    mnesia:start();
                _ ->
                    %% Если есть активная нода, то присоединяемся к ней
                    error_logger:info_msg("[~p:~p] Connect to cluster ~p~n", [?MODULE, ?LINE, LiveNodes]),
                    mnesia:start(),
                    mnesia:change_config(extra_db_nodes, LiveNodes),
                    %% Создаем disc_copies для таблицы schema
                    case mnesia:change_table_copy_type(schema, node(), disc_copies) of
                        {atomic, ok} ->
                            ok;
                        {aborted, Reason} ->
                            error_logger:error_msg("[~p:~p] Error adding to schema, Reason ~p~n", [?MODULE, ?LINE, Reason])
                    end
            end
    end,

    %% Создаем таблицы
    case sip_serv_db:init_db() of
        ok ->
            ok;
        {error, InitReason} ->
            error_logger:error_msg("[~p:~p] Error initializing DB, Reason ~p~n", [?MODULE, ?LINE, InitReason])
    end,
    case mnesia:wait_for_tables([abonent, registration, erlsubscription, publication], 30000) of
        ok ->
            case sip_serv_sup:start_link() of
                {ok, Pid} ->
                    load_abonents(),
                    {ok, Pid};
                {error, SupReason} ->
                    mnesia:stop(),
                    {error, SupReason}
            end;
        {error, WaitReason} ->
            error_logger:error_msg("[~p:~p] Error wait for tables, Reason ~p~n", [?MODULE, ?LINE, WaitReason]),
            mnesia:stop(),
            {error, WaitReason}
    end.

%%--------------------------------------------------------------------
%% @doc
%% Возвращает список активных узлов из заданного списка.
%% @param Nodes список узлов для проверки
%% @param Retries количество попыток повторных проверок активности узла.
%% @return список акивных узлов, доступных в сети
%% @end
%%--------------------------------------------------------------------
-spec live_nodes(Nodes :: list(), Retries :: integer()) -> list().
live_nodes(_Nodes, 0) ->
    [];

live_nodes(Nodes, Retries) ->
    case [N || N <- Nodes, net_adm:ping(N) =:= pong] of
        [] ->
            timer:sleep(1000),
            live_nodes(Nodes, Retries - 1);
        Live ->
            Live
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
            case Aor =:= undefined orelse Password =:= undefined orelse Domain =:= undefined of
                true ->
                    error_logger:warning_msg("[~p:~p] Skipping invalid abonent entry: ~p~n", [?MODULE, ?LINE, AbonentMap]);
                false ->
                    Abonent = #abonent{
                            aor = Aor,
                            password = Password,
                            domain = Domain,
                            create_time = erlang:system_time(second)
                        },
                    mnesia:transaction(fun() -> mnesia:write(Abonent) end)
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