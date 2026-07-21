FROM erlang:21

WORKDIR /app

COPY rebar.config ./

RUN rebar3 deps

COPY . .

RUN mkdir -p /tmp/mnesia

RUN rebar3 compile

CMD rebar3 shell --apps sip_serv --name ${NODE_NAME:-node1@127.0.0.101} --setcookie ${ERLANG_COOKIE:-mysipsecret}