%%%-------------------------------------------------------------------
%%% @author ngq <ngq_scut@126.com>
%%% @doc
%%%     内部服务端处理模块
%%% @end
%%% Created : 19. 一月 2017 16:01
%%%-------------------------------------------------------------------
-module(node_server_base).
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

-record(state, {
    nodes = [],         %% 连接中的节点
    opts = []           %% 节点管理参数
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
    Type = case application:get_env(?NODE_APP, client_type, all) of
        visible -> visible;
        hidden -> hidden;
        _ -> all
    end,
    Opts = [{node_type, Type}, nodedown_reason],
    ok = net_kernel:monitor_nodes(true, Opts),
    Connects = erlang:nodes(connected),
    {ok, #state{nodes = Connects, opts = Opts}}.

handle_cast(Event, State) ->
    ?INFO("Server handle unknown cast:~p", [Event]),
    {noreply, State}.

handle_call(get_info, _From, #state{nodes = Connects} = State) ->
    {reply, Connects, State};
handle_call(Request, _From, State) ->
    ?INFO("Server handle unknown call:~p", [Request]),
    {reply, ok, State}.

handle_info({nodeup, Node, InfoList}, #state{nodes = Connects} = State) ->
    %% 通知节点连接
    mod_node_server:event({nodeup, Node, InfoList}),
    {noreply, State#state{nodes = [Node|Connects]}};
handle_info({nodedown, Node, InfoList}, #state{nodes = Connects} = State) ->
    case lists:member(Node, Connects) of
        true ->
            %% 通知节点关闭
            mod_node_server:event({nodedown, Node, InfoList}),
            {noreply, State#state{
                nodes = lists:delete(Node, Connects)
            }};
        false ->
            {noreply, State}
    end;
handle_info(_Info, State) ->
    {noreply, State}.

terminate(Reason, #state{nodes = Connects, opts = Opts} = _State) ->
    ?INFO("~p terminate:~p", [?MODULE, Reason]),
    net_kernel:monitor_nodes(false, Opts),
    lists:foreach(
        fun(Node) ->
            erlang:disconnect_node(Node),
            mod_node_server:event({nodedown, Node, [{terminate, Reason}]})
        end, Connects),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
