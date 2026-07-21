%% @doc
%% Главный процесс для определения мастера в кластере, реализует поведение gen_server.
%% Периодически проверяет приоритеты узлов и назначает мастером узел
%% с наивысшим приоритетом.
%% Мастер поднимает виртуальный IP и запускает SIP-сурвер.
%% @end
-module(sip_serv_master).

-behaviour(gen_server).

-export([start_link/0, init/1, get_my_priority/0]).
-export([handle_info/2, handle_call/3, handle_cast/2, terminate/2, code_change/3]).

-define(TIMER, 2000).

-type state() :: #{is_master := boolean()}.

%% @doc
%% Запуск сервера как процесса с именем модуля.
%% @returns {ok, pid()} | {error, term()} - результаты запуска gen_server
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc
%% Инициализация состояния сервера. Установка флага is_master в false.
%% Запуск первого вызова проверки мастера.
%% @param [Interval] - список аргументов (не используется)
%% @returns {ok, state()}
-spec init([integer()]) -> {ok, integer()}.
init([]) ->
    erlang:send_after(3000, self(), check_master),
    {ok, #{is_master => false}}.

%% @doc
%% Обработка состояния check_master.
%% Определяет есть ли узел с более высоким приоритетом и при необходимости
%% переключает состояние текущего узла.
%% После обработки запускает следующее проверку через 2 секунды.
%% @param check_expired атом - сообщение от таймера
%% @param State - текущее состояние
%% @returns {noreply, state()} - переход в новое состояние
-spec handle_info(check_master, state()) -> {noreply, state()}.
handle_info(check_master, State) ->
    Node = node(),
    Priority = get_my_priority(),
    Nodes = [Node | nodes()],
    HigherPriority = lists:any(fun(N) ->
        get_node_priority(N) > Priority end, Nodes),
    NewState = case HigherPriority of
        false ->
            become_master(State);
        true ->
            become_slave(State)
    end,
    erlang:send_after(?TIMER, self(), check_master),
    {noreply, NewState};

%% @doc
%% Обработка сообщений, кроме check_master
%% Игнорирует сообщения, не изменяет состояние
%% @param _Infod - любое сообщение
%% @param State - инетрвал текущее состояние
%% @returns {noreply, state()} - состояние не меняется
handle_info(_Info, State) ->
    {noreply, State}.

%% @doc
%% Перевод узла в состояния мастера.
%% Добавляет виртуальный IP на интерфейс lo,
%% запускает SIP-сервер, Cowboy и cache.
%% @param State - текущее состояние
%% @returns новое состояние, при успехе #{is_master => true}, при ошибке возвращает исходное состояние.
-spec become_master(state()) -> state().
become_master(#{is_master := false} = State) ->
    io:format("~n~p: I became a master~n~n", [node()]),
    os:cmd("ip addr add 127.0.0.100/32 dev lo"),
    case sip_serv_sup:start_cache() of
        ok ->
            sip_serv_cache:restore_cache(),
            case sip_serv_sup:start_cowboy() of
                ok ->
                    case sip_serv_sup:start_nksip() of
                        ok ->
                            State#{is_master => true};
                        {error, Reason} ->
                            error_logger:info_msg("[~p:~p] SIP startup Error: ~p~n", [?MODULE, ?LINE, Reason]),
                            sip_serv_sup:stop_nksip(),
                            sip_serv_sup:stop_cowboy(),
                            sip_serv_sup:stop_cache(),
                            os:cmd("ip addr del 127.0.0.100/32 dev lo"),
                            State
                    end;
                {error, Reason} ->
                    error_logger:info_msg("[~p:~p] Cowboy startup Error: ~p~n", [?MODULE, ?LINE, Reason]),
                    sip_serv_sup:stop_cowboy(),
                    sip_serv_sup:stop_cache(),
                    os:cmd("ip addr del 127.0.0.100/32 dev lo"),
                    State
            end;
        {error, Reason} ->
            error_logger:info_msg("[~p:~p] Cache startup Error: ~p~n", [?MODULE, ?LINE, Reason]),
            sip_serv_sup:stop_cache(),
            os:cmd("ip addr del 127.0.0.100/32 dev lo"),
            State
    end;

become_master(State) ->
    State.

%% @doc
%% Снимает статус мастер узла. Останавливает SIP-сервер с помощью sip_serv_sup:stop_nksip/0
%% и удаляет виртуальный IP на интерфейс lo.
%% @param State - текущее состояние
%% @returns новое состояние is_master => false
-spec become_slave(state()) -> state().
become_slave(#{is_master := true} = State) ->
    io:format("~n~p: A master with a higher priority has appeared. I'm giving up the role.~n~n", [node()]),
    sip_serv_sup:stop_nksip(),
    sip_serv_sup:stop_cowboy(),
    sip_serv_sup:stop_cache(),
    os:cmd("ip addr del 127.0.0.100/32 dev lo"),
    State#{is_master => false};

become_slave(State) ->
    State.

%% @doc
%% Получает приоритет узла с помощью RPC-вызова.
%% Если узел недоступен или возвращает некорректное значение,
%% то его приоритет равен 0.
%% @param Node - атом с именем узла
%% @returns Priority - приоритет узла
-spec get_node_priority(Node :: node()) -> integer().
get_node_priority(Node) ->
    case rpc:call(Node, ?MODULE, get_my_priority, []) of
        {badrpc, _} ->
            0;
        Priority when is_integer(Priority) ->
            Priority;
        _ ->
            0
    end.

%% @doc
%% Возвращает приоритет текущего узла, который задан переменной окружения PRIORITY.
%% Если переменная не установлена, врзвращается 100.
%% @returns челое число - приоритет узла
-spec get_my_priority() -> integer().
get_my_priority() ->
    case os:getenv("PRIORITY") of
        false -> 100;
        Str -> list_to_integer(Str)
    end.

%% @doc
%% Обработка синхронных вызовов
%% Все запросы игнорируются
%% @param _Reques - игнорируемый запрос
%% @param _From - информация о вызывающем процессе
%% @param Interval - инетрвал (состояние процесса)
%% @returns {reply, ok, integer()} - состояние не меняется
-spec handle_call(term(), {pid(), term()}, integer()) -> {reply, ok, integer()}.
handle_call(_Request, _From, State) ->
    {reply, ok, State}.

%% @doc
%% Обработка асинхронных вызовов
%% Все запросы игнорируются
%% @param _Reques - игнорируемый запрос
%% @param Interval - инетрвал (состояние процесса)
%% @returns {noreply, integer()} - состояние не меняется
-spec handle_cast(term(), integer()) -> {noreply, integer()}.
handle_cast(_Request, State) ->
    {noreply, State}.

%% @doc
%% Завершение работы gen_server
%% @param _Reason - причина завершения
%% @param _Interval - инетрвал (состояние процесса)
%% @returns ok
-spec terminate(term(), integer()) -> ok.
terminate(_Reason, _State) ->
    ok.

%% @doc
%% Обработка горячей замены кода
%% @param _OldVsn - версия старого модуля
%% @param _Interval - инетрвал (состояние процесса)
%% @param _Extra - дополнительные данные
%% @returns {ok, integer()} - состояние без изменений
-spec code_change(term() | {down, term()}, integer(), term()) -> {ok, integer()}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
