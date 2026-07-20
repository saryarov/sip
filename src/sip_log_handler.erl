%%%-------------------------------------------------------------------
%%% @doc
%%% Обработчик HTTP-запросов для записи статистики в лог-файлы.
%%% Обрабатывает POST-запросы на пути:
%%% - /api/monitor/log
%%% - /api/monitor/log/full
%%% @end
%%%-------------------------------------------------------------------
-module(sip_log_handler).
-export([init/2]).
%%--------------------------------------------------------------------
%% @doc
%% Точка входа Cowboy обработчика.
%% Определяет метод и путь запроса, после чего вызывает соответствующий обработчик.
%%
%% @param Req Cowboy request object
%% @param State Состояние обработчика
%% @return {ok, Req, State}
%% @end
%%--------------------------------------------------------------------
-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    Path = cowboy_req:path(Req),
    case {Method, Path} of
        {<<"POST">>, <<"/api/monitor/log">>} ->
            handle_trigger_log(Req, State);

        {<<"POST">>, <<"/api/monitor/log/full">>} ->
            handle_trigger_log_full(Req, State);

        _ ->
            cowboy_req:reply(404, #{}, <<"Not Found">>, Req)
    end.
%%--------------------------------------------------------------------
%% @doc
%% Обрабатывает POST-запрос на запись краткой статистики в лог.
%% Принимает опциональное поле `filename` в JSON-теле.
%%
%% @param Req Cowboy request object
%% @param State Состояние обработчика
%% @return {ok, Req, State}
%% @end
%%--------------------------------------------------------------------
-spec handle_trigger_log(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
handle_trigger_log(Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    Data = jsx:decode(Body, [return_maps]),
    FileName = maps:get(<<"filename">>, Data, undefined),
    Result = case FileName of
        undefined -> sip_serv_api:monitor_log();
        _ -> sip_serv_api:monitor_log(FileName)
    end,

    case Result of
      ok -> Req3 = cowboy_req:reply(201, #{<<"content-type">> => <<"application/json">>
            }, <<"{\"status\":\"created\"}">>, Req2),
            {ok, Req3, State};
        _ ->  Req3 = cowboy_req:reply(400, #{<<"content-type">> => <<"application/json">>
            }, <<"{\"status\":\"error\"}">>, Req2),
        {ok, Req3, State}
    end.
%%--------------------------------------------------------------------
%% @doc
%% Обрабатывает POST-запрос на запись полной статистики в лог.
%% Принимает опциональное поле `filename` в JSON-теле.
%%
%% @param Req Cowboy request object
%% @param State Состояние обработчика
%% @return {ok, Req, State}
%% @end
%%--------------------------------------------------------------------
-spec handle_trigger_log_full(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
handle_trigger_log_full(Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    Data = jsx:decode(Body, [return_maps]),
    FileName = maps:get(<<"filename">>, Data, undefined),
    Result = case FileName of
        undefined -> sip_serv_api:monitor_full_log();
        _ -> sip_serv_api:monitor_full_log(FileName)
    end,

    case Result of
      ok -> Req3 = cowboy_req:reply(201, #{<<"content-type">> => <<"application/json">>
            }, <<"{\"status\":\"created\"}">>, Req2),
            {ok, Req3, State};
        _ ->  Req3 = cowboy_req:reply(400, #{<<"content-type">> => <<"application/json">>
            }, <<"{\"status\":\"error\"}">>, Req2),
        {ok, Req3, State}
    end.