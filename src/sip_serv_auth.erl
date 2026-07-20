%% @doc
%% Модуль аутентификации - интерфейс для работы с абонентами
%% Содержит функции дя проверки существования обонента, его добавления и удаления
%% Используется nksip через модуль sip_serv_hendler
%% @end

-module(sip_serv_auth).

-include("sip_serv_records.hrl").

-export([authenticate/1]).
-export([add_abonent/2, delete_abonent/1]).

%% @doc
%% Проверка сущестования пользователя в таблице абонентов
%% @param AOR - уникальный идентификатор пользователя (string), искомый в таблице
%% @return Возвращает кортеж {ok, Parrword} или {error, not_found}
-spec authenticate(AOR :: string()) -> {ok, string()} | {error, not_found}.
authenticate(AOR) ->
    sip_serv_db:get_abonent(AOR).

%% @doc
%% Добавление клиента в таблицу абонентов
%% @param AOR - уникальный идентификатор пользователя (string)
%% @param Password - пароль пользователя (string)
%% @return Возвращает кортеж {error, exists}, если пользователь уже существует, кортеж {error, Reason} при ошибке БД, или atom ok, если он добавлен
-spec add_abonent(AOR :: string(), Password :: string()) -> ok | {error, exists | db_error}.
add_abonent(AOR, Password) ->
    case authenticate(AOR) of
        {ok, _} ->
            {error, exists};
        {error, not_found} ->
            Domain = get_domain_form_aor(AOR),
            CreateTime = erlang:system_time(second),
            Abonent = #abonent{
                aor = AOR,
                password = Password,
                domain = Domain,
                create_time = CreateTime
            },
            sip_serv_db:add_abonent(Abonent)
    end.

%% @doc
%% Получение домена из логичесткого идентификатора пользователя
%% @param AOR - уникальный идентификатор пользователя (string)
%% @return Возвращает строку "unknow", если в AOR нет домена, возвращает домен в виде строки, если он присутствует в AOR
-spec get_domain_form_aor(AOR :: string()) -> string().
get_domain_form_aor(AOR) ->
    case string:chr(AOR, $@) of
        0 -> "unknow";
        Pos -> string:substr(AOR, Pos+1)
    end.

%% @doc
%% Удаление клиента из таблицы абонентов
%% @param AOR - уникальный идентификатор пользователя (string)
%% @return Возвращает кортеж {error, not_found}, если пользователь не найден, кортеж {error, Reason} при ошибке БД, или atom ok, если он удален
-spec delete_abonent(AOR :: string()) -> ok | {error, not_found | db_error}.
delete_abonent(AOR) ->
    case authenticate(AOR) of
        {ok, _} ->
            sip_serv_db:delete_abonent(AOR);
        {error, not_found} ->
            {error, not_found}
        end.