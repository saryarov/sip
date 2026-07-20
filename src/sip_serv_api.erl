%%%-------------------------------------------------------------------
%%% @doc
%%% API-слой приложения.
%%% Предоставляет функции для работы с пользователями и мониторингом.
%%% @end
%%%-------------------------------------------------------------------
-module(sip_serv_api).

-export([add_user/2, delete_user/1, monitor_log/0, monitor_full_log/0, monitor_log/1, monitor_full_log/1]).
%%--------------------------------------------------------------------
%% @doc
%% Записывает краткую статистику в лог-файл (по умолчанию `logs/active.log`).
%%
%% @return ok | {error, term()}
%% @end
%%--------------------------------------------------------------------
-spec monitor_log() -> ok | {error, term()}.
monitor_log() ->
    case sip_serv_monitor:log_count_stats() of
        ok ->
            case filelib:is_file("logs/active.log") of
                true  -> ok;
                false -> {error, file_not_created}
            end;
        _ -> {error, file:posix()}
    end.
%%--------------------------------------------------------------------
%% @doc
%% Записывает краткую статистику в указанный лог-файл.
%%
%% @param FileName Имя файла для записи лога (бинар или строка)
%% @return ok | {error, term()}
%% @end
%%--------------------------------------------------------------------
-spec monitor_log(FileName :: binary() | string()) -> ok | {error, term()}.
monitor_log(FileName) ->
    FileNameSting = binary_to_list(FileName),
    case sip_serv_monitor:log_count_stats(FileNameSting) of
        ok ->
            case filelib:is_file(FileName) of
                true  -> ok;
                false -> {error, file_not_created}
            end;
        _ -> {error, file:posix()}
    end.
%%--------------------------------------------------------------------
%% @doc
%% Записывает полную статистику в лог-файл (по умолчанию `logs/active.log`).
%%
%% @return ok | {error, term()}
%% @end
%%--------------------------------------------------------------------
-spec monitor_full_log() -> ok | {error, term()}.
monitor_full_log() ->
    case sip_serv_monitor:log_full_stats() of
        ok ->
            case filelib:is_file("logs/active.log") of
                true  -> ok;
                false -> {error, file_not_created}
            end;
        _ -> {error, file:posix()}
    end.
%%--------------------------------------------------------------------
%% @doc
%% Записывает полную статистику в указанный лог-файл.
%%
%% @param FileName Имя файла для записи лога (бинар или строка)
%% @return ok | {error, term()}
%% @end
%%--------------------------------------------------------------------
-spec monitor_full_log(FileName :: binary() | string()) -> ok | {error, term()}.
monitor_full_log(FileName) ->
    FileNameSting = binary_to_list(FileName),
    case sip_serv_monitor:log_full_stats(FileNameSting) of
        ok ->
            case filelib:is_file(FileName) of
                true  -> ok;
                false -> {error, file_not_created}
            end;
        _ -> {error, file:posix()}
    end.
%%--------------------------------------------------------------------
%% @doc
%% Добавляет нового пользователя в систему.
%% Автоматически приводит `Username` к строке (list).
%%
%% @param Username Имя пользователя (бинар или строка)
%% @param Password Пароль пользователя
%% @return ok | {error, exists} | {error, term()}
%% @end
%%--------------------------------------------------------------------
-spec add_user(AOR :: binary() | string(), Password :: binary() | string()) ->
    ok | {error, exists} | {error, term()}.
add_user(AOR, Password) ->
    AORStr = case AOR of
        Bin when is_binary(Bin) -> binary_to_list(Bin);
        List when is_list(List) -> List;
        _ -> error(badarg)
    end,

    case sip_serv_auth:add_abonent(AORStr, Password) of
        ok -> ok;
        {error, exists} -> {error, exists};
        {error, Reason} -> {error, Reason}
    end.
%%--------------------------------------------------------------------
%% @doc
%% Удаляет пользователя из системы.
%% Автоматически приводит `Username` к строке (list).
%%
%% @param Username Имя пользователя (бинар или строка)
%% @return ok | {error, not_found} | {error, term()}
%% @end
%%--------------------------------------------------------------------
-spec delete_user(AOR :: binary() | string()) ->
    ok | {error, not_found} | {error, term()}.
delete_user(AOR) ->
    AORStr = case AOR of
        Bin when is_binary(Bin) -> binary_to_list(Bin);
        List when is_list(List) -> List;
        _ -> error(badarg)
    end,

    case sip_serv_auth:delete_abonent(AORStr) of
        ok -> ok;
        {error, not_found} -> {error, not_found};
        {error, Reason} -> {error, Reason}
    end.