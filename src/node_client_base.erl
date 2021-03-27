%%%-------------------------------------------------------------------
%%% @author ngq <ngq_scut@126.com>
%%% @doc
%%%     内部客户端处理模块
%%% @end
%%% Created : 19. 一月 2017 16:19
%%%-------------------------------------------------------------------
-module(node_client_base).
-author("ngq").

-behaviour(gen_server).

-include("node_manager.hrl").

%% API
-export([start_link/0]).

%% gen_server callbacks
-export([
    init/1,
    handle_cast/2,
    handle_call/3,
    handle_info/2,
    terminate/2,
    code_change/3
]).

%% 重连定时器
-define(EVENT, reconnect).
-define(RECONNECT_TIMER, erlang:start_timer(1000, self(), ?EVENT)).

-record(state, {
    connect = [],       %% 连接中的节点
    reconnect = [],     %% 需要重连的节点
    ref                 %% 重连定时器
}).

%%%===================================================================
%%% API
%%%===================================================================
%% @doc Creates an event manager
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([]) ->
    erlang:process_flag(priority, high),
    Nodes = lists:ukeysort(1, application:get_env(?NODE_APP, nodes, [])),
    ok = do_init(Nodes),
    {ok, #state{
        connect = [], reconnect = Nodes, ref = ?RECONNECT_TIMER
    }}.

handle_cast(Event, State) ->
    ?INFO("Client handle unknown cast:~p", [Event]),
    {noreply, State}.

handle_call(get_info, _From, #state{connect = Connects} = State) ->
    {reply, Connects, State};
handle_call(Request, _From, State) ->
    ?INFO("Client handle unknown call:~p", [Request]),
    {reply, ok, State}.

handle_info({nodedown, Node}, #state{
    connect = Connects, reconnect = ReConnects, ref = Ref
} = State) ->
    case lists:member(Node, Connects) of
        true ->
            %% 通知节点关闭
            mod_node_client:event({nodedown, Node}),
            {noreply, State#state{
                connect = lists:delete(Node, Connects),
                reconnect = [Node|ReConnects],
                ref = timer(Ref)
            }};
        _ ->
            {noreply, State}
    end;
handle_info({timeout, TimerRef, ?EVENT}, #state{
    connect = Connects, reconnect = ReConnects, ref = TimerRef
} = State) ->
    case do_reconnect(ReConnects, Connects, []) of
        {NewConnects, []} ->
            {noreply, State#state{
                connect = NewConnects, reconnect = [], ref = undefined
            }};
        {NewConnects, NewReConnects} ->
            {noreply, State#state{
                connect = NewConnects, reconnect = NewReConnects, ref = ?RECONNECT_TIMER
            }}
    end;
handle_info(_Info, State) ->
    {noreply, State}.

terminate(Reason, #state{connect = Connects} = _State) ->
    ?INFO("~p terminate:~p", [?MODULE, Reason]),
    lists:foreach(
        fun(Node) ->
            erlang:monitor_node(Node, false),
            erlang:disconnect_node(Node),
            mod_node_client:event({nodedown, Node})
        end, Connects),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
%% 初始化连接
do_init([{Node, Cookie}|T]) ->
    erlang:set_cookie(Node, Cookie),
    true = erlang:monitor_node(Node, true),
    do_init(T);
do_init([]) ->
    ok.

%% 重连节点
do_reconnect([Node|T], Connects, Res) ->
    case net_kernel:connect_node(Node) of
        true ->
            mod_node_client:event({nodeup, Node}),
            do_reconnect(T, [Node|Connects], Res);
        _ ->
            do_reconnect(T, Connects, [Node|Res])
    end;
do_reconnect([], Connects, Res) ->
    {Connects, Res}.

timer(undefined) -> ?RECONNECT_TIMER;
timer(Ref) -> Ref.
