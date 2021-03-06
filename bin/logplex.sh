#!/bin/sh

export USER=logplex
export SERVER_UID=`id -u $USER`
export SERVER_GID=`id -g $USER`
export HOME=/home/logplex

ulimit -n 65535
erl +K true +A100 +P500000 -kernel inet_dist_listen_min 9100 -kernel inet_dist_listen_max 9200 -env ERL_FULLSWEEP_AFTER 0 -env ERL_MAX_PORTS 65535 -name logplex@`hostname --fqdn` -pa ebin -pa deps/*/ebin -noshell -boot release/logplex-1.0
