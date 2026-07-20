%% @doc
%% Модуль мониторинга - сбор статистика из ETS-кэша
%% Выводит время запроса статистики, количество активных подписок и регистраций
%% Выводит результат в файл active.log
%% Вызывается из sip_serv_callback
%% @end

-module(sip_serv_monitor).

-include("sip_serv_records.hrl").

-export([log_count_stats/0, log_count_stats/1,
         log_full_stats/0, log_full_stats/1,
         get_count_stats/0]).

%% @doc
%% Получение количества активных регистраций и подписок из ETS-кэша
%% @return Возвращает кортеж {Reg, Sub}
-spec get_count_stats() -> {integer(), integer()}.
get_count_stats() ->
    sip_serv_cache:get_active_counts().

%% @doc
%% Получение списков активных регистраций и подписок из ETS-кэша
%% @return Возвращает кортеж {[Reg], [Sub]}
-spec get_stats() -> {list(), list()}.
get_stats() ->
    sip_serv_cache:get_active_stats().

%% @doc
%% Запись количества активных регистраций и подписок в файл по умолчанию logs/active.log
%% @return При успешной записи возвращает атом ok, при ошибке (записи в файл или создания каталога) - кортеж {error, file:posix()}
-spec log_count_stats() -> ok | {error, file:posix()}.
log_count_stats() ->
    log_count_stats("logs/active.log").

%% @doc
%% Запись количества активных регистраций и подписок в указанный файл
%% @param Filename полный путь к файлу
%% @return При успешной записи возвращает атом ok, при ошибке (записи в файл или создания каталога) - кортеж {error, file:posix()}
-spec log_count_stats(Filename :: string()) -> ok | {error, file:posix()}.
log_count_stats(Filename) ->
    case is_log_dir() of
        ok ->
            {Reg, Sub} = get_count_stats(),
            Time = time_format(erlang:localtime()),
            Stats = io_lib:format(
                "~s~nActive registrations: ~p~nActive subscriptions: ~p~n~n",
                [Time, Reg, Sub]
            ),
            file:write_file(Filename, Stats, [append]);
        {error, _Reason} ->
            ok
    end.

%% @doc
%% Запись всех активных регистраций и подписок в файл по умолчанию logs/active.log
%% @return При успешной записи возвращает атом ok, при ошибке (записи в файл или создания каталога) - кортеж {error, file:posix()}
-spec log_full_stats() -> ok | {error, file:posix()}.
log_full_stats() ->
    log_full_stats("logs/active.log").

%% @doc
%% Запись всех активных регистраций и подписок в указанный файл
%% @param Filename полный путь к файлу
%% @return При успешной записи возвращает атом ok, при ошибке (записи в файл или создания каталога) - кортеж {error, file:posix()}
-spec log_full_stats(Filename :: string()) -> ok | {error, file:posix()}.
log_full_stats(Filename) ->
    case is_log_dir() of
        ok ->
            {Reg, Sub} = get_stats(),
            Time = time_format(erlang:localtime()),
            RegStr = lists:flatten([registration_format(R) || R <- Reg]),
            SubStr = lists:flatten([subscription_format(S) || S <- Sub]),
            Stats = io_lib:format(
                "~s~nActive registrations: ~n~s~nActive subscriptions: ~n~s~n~n",
                [Time, RegStr, SubStr]
            ),
            file:write_file(Filename, Stats, [append]);
        {error, _Reason} ->
            ok
    end.

%% @doc
%% Создает каталог logs
%% @return При успешном создании или существовании каталога возвращает атом ok,
%% при ошибке - кортеж {error, file:posix()}
-spec is_log_dir() -> ok | {error, file:posix()}.
is_log_dir() ->
    case file:make_dir("logs") of
        ok -> ok;
        {error, eexist} -> ok;
        {error, Reason} -> {error, Reason}
    end.

%% @doc
%% Преобразует временную метку в строку
%% @param {{Year, Month, Day}, {Hour, Minute, Second}}
%% @return Возвращает строку вида YYYY-MM-DD HH:MM:SS
-spec time_format(Date :: tuple()) -> string().
time_format({{Year, Month, Day}, {Hour, Minute, Second}}) ->
    io_lib:format(
        "~4.4.0w-~2.2.0w-~2.2.0w ~2.2.0w:~2.2.0w:~2.2.0w",
        [Year, Month, Day, Hour, Minute, Second]
    ).

%% @doc
%% Преобразует временную метку в строку
%% @param Time количество секунд с 01.01.1970
%% @return Возвращает строку вида YYYY-MM-DD HH:MM:SS
-spec reg_sub_time_format(Time :: integer()) -> string().
reg_sub_time_format(Time) ->
    Base = calendar:datetime_to_gregorian_seconds({{1970,1,1},{0,0,0}}),
    {{Year, Month, Day}, {Hour, Minute, Second}} =
        calendar:gregorian_seconds_to_datetime(Base + Time),
    io_lib:format(
        "~4.4.0w-~2.2.0w-~2.2.0w ~2.2.0w:~2.2.0w:~2.2.0w",
        [Year, Month, Day, Hour, Minute, Second]
    ).

%% @doc
%% Декодирует поле contact записи registration
-spec contact_format(Contact :: list()) -> term().
contact_format(Contact) when is_list(Contact) ->
    try binary_to_term(list_to_binary(Contact)) of
        Term ->
            Term
    catch
        _:_ ->
            Contact
    end;
contact_format(Contact) ->
    Contact.

%% @doc
%% Декодирует поле dialog записи erlsubscription
-spec dialog_format(Dialog :: binary()) -> term().
dialog_format(Dialog) when is_binary(Dialog) ->
    try binary_to_term(Dialog) of
        Term ->
            Term
    catch
        _:_ ->
            Dialog
    end;
dialog_format(Dialog) ->
    Dialog.

%% @doc
%% Форматирует запись регистрации
-spec registration_format(Reg :: #registration{}) -> string().
registration_format(
    #registration{
        aor = Aor,
        contact = Contact,
        expires_time = ExpiresTime,
        registered_time = RegisteredTime
    }) ->
    FormContact = contact_format(Contact),
    FormTime = reg_sub_time_format(RegisteredTime),
    Expires = ExpiresTime - RegisteredTime,
    io_lib:format(
        "  AOR: ~s~n  Contact: ~p~n  ExpiresTime: ~p~n  RegisteredTime: ~s~n~n",
        [Aor, FormContact, Expires, FormTime]
    ).

%% @doc
%% Форматирует запись подписки
-spec subscription_format(Sub :: #erlsubscription{}) -> string().
subscription_format(
    #erlsubscription{
        id = Id,
        aor = Aor,
        subscriber = Subscriber,
        dialog_id = DialogId,
        expires_time = ExpiresTime,
        subscribed_time = SubscribedTime
    }) ->
    FormDialog = dialog_format(DialogId),
    FormTime = reg_sub_time_format(SubscribedTime),
    Expires = ExpiresTime - SubscribedTime,
    io_lib:format(
        "Id: ~p~n  AOR: ~s~n  Subscriber: ~s~n  Dialog: ~p~n  ExpiresTime: ~p~n  SubscribedTime: ~s~n~n",
        [Id, Aor, Subscriber, FormDialog, Expires, FormTime]
    ).