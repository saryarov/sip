-module(sip_stats_handler).

-export([init/2]).

init(Req, State) ->
    Stats = sip_serv_api:get_stats(),

    Body = jsx:encode(Stats),

    Req2 = cowboy_req:reply(200,
        #{<<"content-type">> => <<"application/json">>},
        Body, Req),
    {ok, Req2, State}.
