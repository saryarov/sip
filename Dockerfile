FROM erlang:21

WORKDIR /app

COPY rebar.config ./

RUN rebar3 deps

COPY . .

RUN mkdir -p /tmp/mnesia

RUN rebar3 compile

CMD  ["rebar3", "shell", "--apps", "sip_serv", "--sname", "node1"]