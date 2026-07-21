#!/bin/bash

rm -f *.log

set -e

echo "Регистрация user2"
sipp localhost -sf reg.xml -m 1 -timeout 5 -key user user2 -au user2 -ap user2 -auth_uri sip:localhost -trace_msg -trace_err

echo "Регистрация user1"
sipp localhost -sf reg.xml -m 1 -timeout 5 -key user user1 -au user1 -ap user1 -auth_uri sip:localhost -trace_msg -trace_err

echo "Подписка user1 на user2"
sipp localhost -sf sub.xml -m 1 -timeout 5 -key subscriber user1 -key presentity user2 -trace_msg -trace_err

echo "Все тесты успешно пройдены!"