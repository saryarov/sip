%% @doc
%% Модуль-таймер для периодической очистки истекших регистраций и подписок
%% Реализует поведение gen_server, каждые N сукенд вызивает sip_serv_db:delete_expired()
%% По умолчанию интервал - 15 секунд, его можно задать при старте в супервизоре
%% @end

-module(sip_serv_cleanup).
-behaviour(gen_server).

-export([start_link/0, start_link/1]).
-export([init/1, handle_info/2, handle_call/3, handle_cast/2, terminate/2, code_change/3]).

%% @doc
%% Запуск таймера с интервалом по умолчанию (15 секунд)
%% @returns {ok, pid()} | {error, term()} - результаты запуска gen_server
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    start_link(15000).

%% @doc
%% Запуск таймера с заданным интервалом
%% @param Interval интервал медлу вызовами функции очистки в силлисекундах
%% @returns {ok, pid()} | {error, term()} - результаты запуска gen_server
-spec start_link(Interval :: integer()) -> {ok, pid()} | {error, term()}.
start_link(Interval) when is_integer(Interval), Interval > 0 ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [Interval], []).

%% @doc
%% Инициализация gen_server
%% Сохраняет интервал очистки в состоянии провесса и запускает первый таймер
%% @param [Interval] - список с интервалом
%% @returns {ok, pid()} | {error, term()} - результаты запуска gen_server
-spec init([integer()]) -> {ok, integer()}.
init([Interval]) ->
    erlang:send_after(Interval, self(), check_expired),
    {ok, Interval}.

%% @doc
%% Обработка состояния check_expired
%% Вызывает очистку истекших записей через sip_serv_db:delete_expired()
%% Логирует ошибку при неудаче и перезапускает таймер
%% @param check_expired атом - сообщение от таймера
%% @param Interval - инетрвал (состояние процесса)
%% @returns {noreply, integer()} - состояние не меняется
-spec handle_info(term(), integer()) -> {noreply, integer()}.
handle_info(check_expired, Interval) ->
    case sip_serv_db:delete_expired() of
        ok ->
            ok;
        {error, Reason} ->
            logger:warning("~p: elete_expired failed: ~p", [?MODULE, Reason])
    end,
    erlang:send_after(Interval, self(), check_expired),
    {noreply, Interval};

%% @doc
%% Обработка сообщений, кроме check_expired
%% Игнорирует сообщения, не изменяет состояние
%% @param _Infod - любое сообщение
%% @param Interval - инетрвал (состояние процесса)
%% @returns {noreply, integer()} - состояние не меняется
handle_info(_Info, Interval) ->
    {noreply, Interval}.

%% @doc
%% Обработка синхронных вызовов
%% Все запросы игнорируются
%% @param _Reques - игнорируемый запрос
%% @param _From - информация о вызывающем процессе
%% @param Interval - инетрвал (состояние процесса)
%% @returns {reply, ok, integer()} - состояние не меняется
-spec handle_call(term(), {pid(), term()}, integer()) -> {reply, ok, integer()}.
handle_call(_Request, _From, Interval) ->
    {reply, ok, Interval}.

%% @doc
%% Обработка асинхронных вызовов
%% Все запросы игнорируются
%% @param _Reques - игнорируемый запрос
%% @param Interval - инетрвал (состояние процесса)
%% @returns {noreply, integer()} - состояние не меняется
-spec handle_cast(term(), integer()) -> {noreply, integer()}.
handle_cast(_Request, Interval) ->
    {noreply, Interval}.

%% @doc
%% Завершение работы gen_server
%% @param _Reason - причина завершения
%% @param _Interval - инетрвал (состояние процесса)
%% @returns ok
-spec terminate(term(), integer()) -> ok.
terminate(_Reason, _Interval) ->
    ok.

%% @doc
%% Обработка горячей замены кода
%% @param _OldVsn - версия старого модуля
%% @param _Interval - инетрвал (состояние процесса)
%% @param _Extra - дополнительные данные
%% @returns {ok, integer()} - состояние без изменений
-spec code_change(term() | {down, term()}, integer(), term()) -> {ok, integer()}.
code_change(_OldVsn, Interval, _Extra) ->
    {ok, Interval}.