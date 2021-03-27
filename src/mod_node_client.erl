%%%-------------------------------------------------------------------
%%% @author ngq <ngq_scut@126.com>
%%% @doc
%%%     客户端节点处理模块
%%% @end
%%% Created : 04. 一月 2019 11:53
%%%-------------------------------------------------------------------
-module(mod_node_client).
-author("ngq").

-include("node_manager.hrl").

%% API
-export([
    start_link/0,
    start_handler/1,
    event/1
]).

-define(SERVER, ?MODULE).

%%%===================================================================
%%% API
%%%===================================================================
%% @doc Creates an event manager
start_link() ->
    gen_event:start_link({local, ?SERVER}).

%% @doc 初始化客户节点
start_handler(Handlers) ->
    Done = gen_event:which_handlers(?SERVER),
    Start = Handlers -- Done,
    lists:foreach(
        fun(Handler) ->
            ok = gen_event:add_handler(?SERVER, Handler, [])
        end, Start).

%% @doc 异步事件
event(Event) ->
    gen_event:notify(?SERVER, Event).

%%%===================================================================
%%% Internal functions
%%%===================================================================
