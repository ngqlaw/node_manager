%%%-------------------------------------------------------------------
%%% @author ngq <ngq_scut@126.com>
%%% @doc
%%% 客户端节点处理模块
%%% @end
%%% Created : 04. 一月 2019 11:53
%%%-------------------------------------------------------------------
-module(mod_node_client).
-author("ngq").

-behaviour(gen_event).

-include("node_manager.hrl").

%% API
-export([
    start_link/0,
    add_handler/2,
    start_handler/1,
    event/1,
    call/1,
    node_connect/1,
    node_down/2
]).

%% gen_event callbacks
-export([
    init/1,
    handle_event/2,
    handle_call/2,
    handle_info/2,
    terminate/2,
    code_change/3
]).

-define(SERVER, ?MODULE).

-record(state, {}).

%%%===================================================================
%%% API
%%%===================================================================
%% @doc Creates an event manager
start_link() ->
    gen_event:start_link({local, ?SERVER}).

%% @doc Adds an event handler
add_handler(Handler, Args) ->
    gen_event:add_handler(?SERVER, Handler, Args).

%% @doc 初始化客户节点
start_handler(Handlers) ->
    Done = gen_event:which_handlers(?SERVER),
    Start = [?MODULE|Handlers] -- Done,
    lists:foreach(fun(Handler) -> ok = add_handler(Handler, []) end, Start).

%% @doc 异步事件
event(Event) ->
    gen_event:notify(?SERVER, Event).

%% @doc 同步事件
call(Event) ->
    case gen_event:which_handlers(?SERVER) of
        [Handler] ->
            gen_event:call(?SERVER, Handler, Event);
        L ->
            [{Handler, gen_event:call(?SERVER, Handler, Event)} || Handler <- L]
    end.

%% @doc 节点连接
node_connect(Type) ->
    gen_event:notify(?SERVER, {server_connect, Type}).

%% @doc 节点关闭
node_down(Type, Node) ->
    gen_event:notify(?SERVER, {server_nodedown, Type, Node}).

%%%===================================================================
%%% gen_event callbacks
%%%===================================================================

init([]) ->
    {ok, #state{}}.

handle_event(_Event, State) ->
    {ok, State}.

handle_call(_Request, State) ->
    {ok, ok, State}.

handle_info(_Info, State) ->
    {ok, State}.

terminate(_Arg, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
