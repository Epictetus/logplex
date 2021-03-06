%% Copyright (c) 2010 Jacob Vorreuter <jacob.vorreuter@gmail.com>
%% 
%% Permission is hereby granted, free of charge, to any person
%% obtaining a copy of this software and associated documentation
%% files (the "Software"), to deal in the Software without
%% restriction, including without limitation the rights to use,
%% copy, modify, merge, publish, distribute, sublicense, and/or sell
%% copies of the Software, and to permit persons to whom the
%% Software is furnished to do so, subject to the following
%% conditions:
%% 
%% The above copyright notice and this permission notice shall be
%% included in all copies or substantial portions of the Software.
%% 
%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
%% EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
%% OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
%% NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
%% HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
%% WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
%% FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
%% OTHER DEALINGS IN THE SOFTWARE.
-module(logplex_app).
-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).

-export([logplex_work_queue_args/0
         ,nsync_opts/0
         ,config/0
         ,config/1
         ,config/2
        ]).

-include("logplex.hrl").
-include("logplex_logging.hrl").

%% ===================================================================
%% Application callbacks
%% ===================================================================

start(_StartType, _StartArgs) ->
    ?INFO("at=start", []),
    set_cookie(),
    read_git_branch(),
    read_availability_zone(),
    boot_pagerduty(),
    application:start(redis),
    setup_redgrid_vals(),
    application:start(nsync),
    application:start(cowboy),
    logplex_sup:start_link().

stop(_State) ->
    ?INFO("at=stop", []),
    ok.

set_cookie() ->
    case os:getenv("LOGPLEX_COOKIE") of
        false -> ok;
        Cookie -> erlang:set_cookie(node(), list_to_atom(Cookie))
    end.

read_git_branch() ->
    GitOutput = hd(string:tokens(os:cmd("git status"), "\n")),
    case re:run(GitOutput, "\# On branch (\\S+)", [{capture, all_but_first, list}]) of
        {match,[Branch]} ->
            application:set_env(logplex, git_branch, Branch);
        _ ->
            ok
    end.

read_availability_zone() ->
    case httpc:request("http://169.254.169.254/latest/meta-data/placement/availability-zone") of
        {ok,{{_,200,_}, _Headers, Zone}} ->
            application:set_env(logplex, availability_zone, Zone);
        _ ->
            ok
    end.

boot_pagerduty() ->
    case os:getenv("HEROKU_DOMAIN") of
        "heroku.com" ->
            case os:getenv("PAGERDUTY") of
                "0" -> ok;
                _ ->
                    ok = application:load(pagerduty),
                    application:set_env(pagerduty, service_key, os:getenv("ROUTING_PAGERDUTY_SERVICE_KEY")),
                    ok = application:start(pagerduty, temporary),
                    ok = error_logger:add_report_handler(logplex_report_handler)
            end;
        _ ->
            ok
    end.

setup_redgrid_vals() ->
    application:load(redgrid),
    application:set_env(redgrid, local_ip, os:getenv("LOCAL_IP")),
    application:set_env(redgrid, redis_url, os:getenv("LOGPLEX_STATS_REDIS_URL")),
    application:set_env(redgrid, domain, os:getenv("HEROKU_DOMAIN")),
    ok.

logplex_work_queue_args() ->
    MaxLength =
        case os:getenv("LOGPLEX_QUEUE_LENGTH") of
            false -> ?DEFAULT_LOGPLEX_QUEUE_LENGTH;
            StrNum1 -> list_to_integer(StrNum1)
        end,
    NumWorkers =
        case os:getenv("LOGPLEX_WORKERS") of
            false -> ?DEFAULT_LOGPLEX_WORKERS;
            StrNum2 -> list_to_integer(StrNum2)
        end,
    [{name, "logplex_work_queue"},
     {max_length, MaxLength},
     {num_workers, NumWorkers},
     {worker_sup, logplex_worker_sup},
     {worker_args, []}].

nsync_opts() ->
    RedisOpts = logplex_utils:redis_opts("LOGPLEX_CONFIG_REDIS_URL"),
    Ip = case proplists:get_value(ip, RedisOpts) of
        {_,_,_,_}=L -> string:join([integer_to_list(I) || I <- tuple_to_list(L)], ".");
        Other -> Other
    end,
    RedisOpts1 = proplists:delete(ip, RedisOpts),
    RedisOpts2 = [{host, Ip} | RedisOpts1],
    [{callback, {nsync_callback, handle, []}} | RedisOpts2].


config(Key, Default) ->
    case application:get_env(logplex, Key) of
        undefined -> Default;
        {ok, Val} -> Val
    end.

config(redis_stats_uri) ->
    redo_uri:parse(os:getenv("LOGPLEX_STATS_REDIS_URL"));
config(Key) ->
    case application:get_env(logplex, Key) of
        undefined -> erlang:error({missing_config, Key});
        {ok, Val} -> Val
    end.

config() ->
    application:get_all_env(logplex).
