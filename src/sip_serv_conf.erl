-module(sip_serv_conf).

-export([get_abonents/0]).

%%--------------------------------------------------------------------
%% @doc Возвращает список абонентов из конфигурационного файла.
%% @end
%%--------------------------------------------------------------------
-spec get_abonents() -> [map()].
get_abonents() ->
    case application:get_env(sip_serv, abonents) of
        {ok, Abonents} ->
            Abonents;
        undefined ->
            [];
        _ ->
            []
    end.