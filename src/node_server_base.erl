%%%-------------------------------------------------------------------
%%% @author ngq <ngq_scut@126.com>
%%% @doc
%%% 内部服务端处理模块
%%% @end
%%% Created : 19. 一月 2017 16:01
%%%-------------------------------------------------------------------
-module(node_server_base).
-author("ngq").

-behaviour(gen_server).

-include("node_manager.hrl").

%% API
-export([
    start_link/0,
    check/0,
    remote_action/2,
    remote_call/2
]).

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
    connect_nodes = []     %% 连接中的节点
}).

%%%===================================================================
%%% API
%%%===================================================================
%% @doc Creates an event manager
start_link() ->
    gen_server:start_link({local, ?NODE_SERVER}, ?MODULE, [], []).

%% @doc 检查服务节点是否启动
check() ->
    case erlang:whereis(?NODE_SERVER) of
        Pid when erlang:is_pid(Pid) ->
            erlang:is_process_alive(Pid);
        _ ->
            false
    end.

%% @doc 往客户节点发送消息（异步）
remote_action(Node, Msg) ->
    gen_server:cast(?NODE_CLIENT, {action_server, Node, Msg}).

%% @doc 往客户节点发送消息（同步）
remote_call(Node, Msg) ->
    gen_server:call(?NODE_CLIENT, {call_server, Node, Msg}).

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
    ok = net_kernel:monitor_nodes(true, [{node_type, Type}, nodedown_reason]),
    {ok, #state{
        connect_nodes = []
    }}.

handle_cast(Event, State) ->
    case catch do_handle_cast(Event, State) of
        {ok, NewState} ->
            {noreply, NewState};
        Error ->
            error_logger:error_msg("Server handle [~p] fail:~p", [Event, Error]),
            {noreply, State}
    end.

do_handle_cast({action_server, Node, Msg}, #state{
    connect_nodes = Connects
} = State) ->
    case Node == all of
        true ->
            rpc:abcast(Connects, ?NODE_CLIENT, {server, Msg});
        false ->
            case lists:member(Node, Connects) of
                true ->
                    gen_server:cast({?NODE_CLIENT, Node}, {server, Msg});
                false ->
                    skip
            end
    end,
    {ok, State};
do_handle_cast({client, Msg}, State) ->
    mod_node_client:event(Msg),
    {ok, State};
do_handle_cast(_Event, #state{} = State) ->
    {ok, State}.

handle_call(Request, _From, State) ->
    case catch do_handle_call(Request, State) of
        {ok, Reply, NewState} ->
            {reply, Reply, NewState};
        Error ->
            {reply, {error, Error}, State}
    end.

do_handle_call({call_server, Node, Msg}, #state{
    connect_nodes = Connects
} = State) ->
    Reply = case Node == all of
        true ->
            rpc:multi_server_call(Connects, ?NODE_CLIENT, {server, Msg});
        false ->
            case lists:member(Node, Connects) of
                true ->
                    gen_server:call({?NODE_CLIENT, Node}, {server, Msg});
                false ->
                    {error, {not_exist, Node}}
            end
    end,
    {ok, Reply, State};
do_handle_call(get_info, #state{
    connect_nodes = Connects
} = State) ->
    {ok, Connects, State};
do_handle_call({client, Msg}, State) ->
    Reply = mod_node_client:call(Msg),
    {ok, Reply, State}.

handle_info({nodeup, Node, _InfoList}, #state{
    connect_nodes = Connects
} = State) ->
    case rpc:call(Node, ?NODE_CLIENT, check, [node()]) of
        true ->
            % 通知节点连接
            mod_node_server:node_connect(Node),
            {noreply, State#state{
                connect_nodes = [Node|Connects]
            }};
        _ ->
            {noreply, State}
    end;
handle_info({nodedown, Node, _InfoList}, #state{
    connect_nodes = Connects
} = State) ->
    case lists:member(Node, Connects) of
        true ->
            % 通知节点关闭
            mod_node_server:node_down(Node),
            {noreply, State#state{
                connect_nodes = lists:delete(Node, Connects)
            }};
        false ->
            {noreply, State}
    end;
handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Arg, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
