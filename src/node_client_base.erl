%%%-------------------------------------------------------------------
%%% @author ngq <ngq_scut@126.com>
%%% @doc
%%% 内部客户端处理模块
%%% @end
%%% Created : 19. 一月 2017 16:19
%%%-------------------------------------------------------------------
-module(node_client_base).
-author("ngq").

-behaviour(gen_server).

-include("node_manager.hrl").

%% API
-export([
    start_link/0,
    check/1,
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

%% 重连定时器
-define(RECONNECT_TIMER, erlang:start_timer(30000, self(), reconnect)).

-record(state, {
    connect_nodes = [],     % 连接中的节点
    reconnect_nodes = [],   % 需要重连的节点
    reconnect_ref           % 重连定时器
}).

%%%===================================================================
%%% API
%%%===================================================================
%% @doc Creates an event manager
start_link() ->
    gen_server:start_link({local, ?NODE_CLIENT}, ?MODULE, [], []).

%% @doc 检查客户节点是否启动
check(Node) ->
    case catch gen_server:call(?NODE_CLIENT, {server_connect, Node}) of
        true ->
            true;
        Error ->
            error_logger:error_msg("Connect client fail:~p", [Error]),
            false
    end.

%% @doc 往服务节点发送消息（异步）
remote_action(Type, Msg) ->
    gen_server:cast(?NODE_CLIENT, {action_client, Type, Msg}).

%% @doc 往服务节点发送消息（同步）
remote_call(Type, Msg) ->
    gen_server:call(?NODE_CLIENT, {call_client, Type, Msg}).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([]) ->
    erlang:process_flag(priority, high),
    {ok, Nodes} = application:get_env(?NODE_APP, nodes),
    State = do_init(Nodes, [], []),
    {ok, State}.

handle_cast(Event, State) ->
    case catch do_handle_cast(Event, State) of
        {ok, NewState} ->
            {noreply, NewState};
        Error ->
            error_logger:error_msg("Client handle [~p] fail:~p", [Event, Error]),
            {noreply, State}
    end.

do_handle_cast({action_client, Type, Msg}, #state{
    connect_nodes = Connects
} = State) ->
    case Type == all of
        true ->
            Nodes = [Node || #node{node = Node} <- Connects],
            rpc:abcast(Nodes, ?NODE_SERVER, {client, Msg});
        false ->
            case lists:keyfind(Type, #node.type, Connects) of
                #node{node = Node} ->
                    gen_server:cast({?NODE_SERVER, Node}, {client, Msg});
                _ ->
                    skip
            end
    end,
    {ok, State};
do_handle_cast({connect, Type, Node, Cookie}, #state{
    connect_nodes = Connects,
    reconnect_nodes = ReConnects
} = State) ->
    case has_node(Node, Connects, ReConnects) of
        true ->
            {ok, State};
        false ->
            Record = #node{
                node = Node,
                cookie = Cookie,
                type = Type
            },
            case catch do_connect(Record) of
                true ->
                    {ok, State#state{
                        connect_nodes = [Record|Connects]
                    }};
                _ ->
                    {ok, State#state{
                        reconnect_nodes = [Record|ReConnects],
                        reconnect_ref = ?RECONNECT_TIMER
                    }}
            end
    end;
do_handle_cast({disconnect, Type}, #state{
    connect_nodes = Nodes,
    reconnect_nodes = ReConnects
} = State) ->
    Fun = fun(#node{type = T}) -> T == Type end,
    case lists:partition(Fun, Nodes) of
        {[], _} ->
            {_, NewReConnects} = lists:partition(Fun, ReConnects),
            {ok, State#state{
                reconnect_nodes = NewReConnects
            }};
        {L, NewNodes} ->
            UpdateReConnects = do_disconnect(L, ReConnects),
            {_, NewReConnects} = lists:partition(Fun, UpdateReConnects),
            {ok, State#state{
                connect_nodes = NewNodes,
                reconnect_nodes = NewReConnects
            }}
    end;
do_handle_cast({server, Msg}, State) ->
    mod_node_server:event(Msg),
    {ok, State};
do_handle_cast(_Event, State) ->
    {ok, State}.

handle_call(Request, _From, State) ->
    case catch do_handle_call(Request, State) of
        {ok, Reply, NewState} ->
            {reply, Reply, NewState};
        Error ->
            {reply, {error, Error}, State}
    end.

do_handle_call({call_client, Type, Msg}, #state{
    connect_nodes = Connects
} = State) ->
   Reply = case Type == all of
        true ->
            Nodes = [Node || #node{node = Node} <- Connects],
            rpc:multi_server_call(Nodes, ?NODE_SERVER, {client, Msg});
        false ->
            case lists:keyfind(Type, #node.type, Connects) of
                #node{node = Node} ->
                    gen_server:call({?NODE_SERVER, Node}, {client, Msg});
                false ->
                    {error, {not_exist, Type}}
            end
    end,
    {ok, Reply, State};
do_handle_call({server_connect, Node}, #state{
    connect_nodes = Connects
} = State) ->
    Reply = case lists:keyfind(Node, #node.node, Connects) of
        #node{type = Type} ->
            % 通知节点连接
            mod_node_client:node_connect(Type),
            true;
        false ->
            false
    end,
    {ok, Reply, State};
do_handle_call(get_info, #state{
    connect_nodes = Connects
} = State) ->
    {ok, Connects, State};
do_handle_call({server, Msg}, State) ->
    Reply = mod_node_server:call(Msg),
    {ok, Reply, State}.

handle_info({nodedown, Node}, #state{
    connect_nodes = Connects,
    reconnect_nodes = ReConnects
} = State) ->
    case lists:keytake(Node, #node.node, Connects) of
        {value, Record, NewConnects} ->
            % 通知节点关闭
            mod_node_client:node_down(Record#node.type, Node),
            {noreply, State#state{
                connect_nodes = NewConnects,
                reconnect_nodes = [Record|ReConnects],
                reconnect_ref = ?RECONNECT_TIMER
            }};
        _ ->
            {noreply, State}
    end;
handle_info({timeout, TimerRef,reconnect}, #state{
    connect_nodes = Connects,
    reconnect_nodes = ReConnects,
    reconnect_ref = TimerRef
} = State) ->
    {NewConnects, NewReConnects} = do_reconnect(ReConnects, Connects, []),
    NewTimer =
        case NewReConnects of
            [] ->
                undefined;
            _ ->
                ?RECONNECT_TIMER
        end,
    {noreply, State#state{
        connect_nodes = NewConnects,
        reconnect_nodes = NewReConnects,
        reconnect_ref = NewTimer
    }};
handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Arg, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

%% 初始化连接
do_init([{Type, Node, Cookie}|T], Connect, ReConnect) ->
    case has_node(Node, Connect, ReConnect) of
        true ->
            do_init(T, Connect, ReConnect);
        false ->
            Record = #node{
                node = Node,
                cookie = Cookie,
                type = Type
            },
            case catch do_connect(Record) of
                true ->
                    do_init(T, [Record|Connect], ReConnect);
                _ ->
                    do_init(T, Connect, [Record|ReConnect])
            end
    end;
do_init([], Connect, []) ->
    #state{
        connect_nodes = Connect,
        reconnect_nodes = []
    };
do_init([], Connect, ReConnect) ->
    #state{
        connect_nodes = Connect,
        reconnect_nodes = ReConnect,
        reconnect_ref = ?RECONNECT_TIMER
    }.

%% 连接节点
do_connect(#node{node = Node, cookie = Cookie}) ->
    erlang:set_cookie(Node, Cookie),
    case rpc:call(Node, ?NODE_SERVER, check, []) of
        true ->
            erlang:monitor_node(Node, true);
        false ->
            false
    end.

%% 重连节点
do_reconnect([Record|T], Connects, Res) ->
    case catch do_connect(Record) of
        true ->
            do_reconnect(T, [Record|Connects], Res);
        _ ->
            do_reconnect(T, Connects, [Record|Res])
    end;
do_reconnect([], Connects, Res) ->
    {Connects, Res}.

%% 断开节点连接
do_disconnect([#node{node = Node} = Record|T], Res) ->
    erlang:disconnect_node(Node),
    do_disconnect(T, [Record|Res]);
do_disconnect([], Res) ->
    Res.

%% 节点是否已存在
has_node(Node, Connect, ReConnect) ->
    lists:keymember(Node, #node.node, Connect) orelse
        lists:keymember(Node, #node.node, ReConnect).
