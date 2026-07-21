%%%-------------------------------------------------------------------
%%% @doc
%%% Обработчик HTTP-запросов для работы с пользователями.
%%% Обрабатывает создание и удаление пользователей через REST API.
%%% @end
%%%-------------------------------------------------------------------
-module(sip_user_handler).
-export([init/2]).
%%--------------------------------------------------------------------
%% @doc
%% Точка входа Cowboy обработчика.
%% Определяет метод HTTP-запроса и вызывает соответствующий обработчик.
%%
%% @param Req Cowboy request object
%% @param State Состояние обработчика
%% @return {ok, Req, State} | {stop, Req, State}
%% @end
%%--------------------------------------------------------------------
-spec init(cowboy_req:req(), any()) ->
    {ok, cowboy_req:req(), any()} |
    {stop, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    case Method of
        <<"GET">>    -> handle_get(Req, State);
        <<"POST">> -> handle_post(Req, State);
        <<"DELETE">> -> handle_delete(Req, State);
        _ -> Req2 = cowboy_req:reply(405, #{}, <<"Method Not Allowed">>, Req),
    {ok, Req2, State}
    end.
%%--------------------------------------------------------------------
%% @doc
%% Обрабатывает POST-запрос на создание нового пользователя.
%% Ожидает JSON с полями username и password.
%%
%% @param Req Cowboy request object
%% @param State Состояние обработчика
%% @return {ok, Req, State}
%% @end
%%--------------------------------------------------------------------
-spec handle_post(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
handle_post(Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    Data = jsx:decode(Body, [return_maps]),
    AorBin = maps:get(<<"aor">>, Data),
    PasswordBin = maps:get(<<"password">>, Data),
    Aor = binary_to_list(AorBin),
    Password = binary_to_list(PasswordBin),
    case sip_serv_api:add_user(Aor, Password) of
        ok ->
            Req3 = cowboy_req:reply(201, #{<<"content-type">> => <<"application/json">>
            }, <<"{\"status\":\"created\"}">>, Req2),
        {ok, Req3, State};
        {error, exists} -> Req3 = cowboy_req:reply(409, #{<<"content-type">> => <<"application/json">>
            }, <<"{\"status\":\"exists\"}">>, Req2),
        {ok, Req3, State};
        {error, _} -> Req3 = cowboy_req:reply(400, #{<<"content-type">> => <<"application/json">>
            }, <<"{\"status\":\"error\"}">>, Req2),
        {ok, Req3, State}
    end.
%%--------------------------------------------------------------------
%% @doc
%% Обрабатывает DELETE-запрос на удаление пользователя.
%% Имя пользователя берётся из пути (:username).
%%
%% @param Req Cowboy request object
%% @param State Состояние обработчика
%% @return {ok, Req, State}
%% @end
%%--------------------------------------------------------------------
-spec handle_delete(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
handle_delete(Req, State) ->
    case cowboy_req:binding(aor, Req) of
        undefined ->
            Req2 = cowboy_req:reply(400, #{}, <<"Missing aor">>, Req),
            {ok, Req2, State};

        AorBin ->
            Aor = binary_to_list(AorBin),

            case sip_serv_api:delete_user(Aor) of
                ok ->
                    Req2 = cowboy_req:reply(204, #{}, <<>>, Req),
                    {ok, Req2, State};
                {error, not_found} ->
                    Req2 = cowboy_req:reply(404, #{}, <<>>, Req),
                    {ok, Req2, State};
                {error, _} ->
                    Req2 = cowboy_req:reply(400, #{}, <<>>, Req),
                    {ok, Req2, State}
            end
    end.
%%--------------------------------------------------------------------
%% @doc
%% Обрабатывает GET-запрос на получение списка всех абонентов.
%% Возвращает JSON вида {"users":[{"aor":"..."}, ...]} без паролей.
%%
%% @param Req Cowboy request object
%% @param State Состояние обработчика
%% @return {ok, Req2, State}
%% @end
%%--------------------------------------------------------------------
handle_get(Req, State) ->
    case sip_serv_api:get_users() of
        {ok, Users} ->
            Body = jsx:encode(#{<<"users">> => Users}),
            Req2 = cowboy_req:reply(200, #{
                <<"content-type">> => <<"application/json">>
            }, Body, Req),
            {ok, Req2, State};
        {error, _} ->
            Req2 = cowboy_req:reply(500, #{
                <<"content-type">> => <<"application/json">>
            }, <<"{\"status\":\"error\"}">>, Req),
            {ok, Req2, State}
    end.