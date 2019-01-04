%%%-------------------------------------------------------------------
%%% @author ngq <ngq_scut@126.com>
%%% @doc
%%%
%%% @end
%%% Created : 19. 一月 2017 16:19
%%%-------------------------------------------------------------------
-module(node_client_base).
-author("ngq").

-behaviour(gen_event).

-include("node_manager.hrl").

%% API
-export([
    start_link/0,
    add_handler/2,
    start_handler/0,
    check/1
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

-record(state, {
    connect_nodes = [],     % 连接中的节点
    reconnect_nodes = [],   % 需要重连的节点
    reconnect_ref           % 重连定时器
}).

%%%===================================================================
%%% gen_event callbacks
%%%===================================================================
%% @doc Creates an event manager
start_link() ->
    gen_event:start_link({local, ?NODE_CLIENT}).

%% @doc Adds an event handler
add_handler(Handler, Args) ->
    gen_event:add_handler(?NODE_CLIENT, Handler, Args).

%% @doc 初始化客户节点
start_handler() ->
    ClientMonitorRef = erlang:monitor(process, ?NODE_CLIENT),
    Done = gen_event:which_handlers(?NODE_CLIENT),
    {ok, ClientHandlers} = application:get_env(?NODE_APP, client_ext_handle),
    Handles = [
        begin
            ok = add_handler(CHandler, []),
            CHandler
        end || CHandler <- ClientHandlers ++ [?MODULE], not lists:member(CHandler, Done)
    ],
    {ClientMonitorRef, Handles}.

%% @doc 检查客户节点是否启动
check(Node) ->
    case catch gen_event:call(?NODE_CLIENT, ?MODULE, {server_connect, Node}) of
        Boolean when is_boolean(Boolean) ->
            Boolean;
        Error ->
            lager:error("Connect client fail:~p", [Error]),
            false
    end.

%%%===================================================================
%%% gen_event callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever a new event handler is added to an event manager,
%% this function is called to initialize the event handler.
%%
%% @end
%%--------------------------------------------------------------------
-spec(init(InitArgs :: term()) ->
    {ok, State :: #state{}} |
    {ok, State :: #state{}, hibernate} |
    {error, Reason :: term()}).
init([]) ->
    erlang:process_flag(priority, high),
    {ok, Nodes} = application:get_env(?NODE_APP, nodes),
    State = do_init(Nodes, [], []),
    {ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever an event manager receives an event sent using
%% gen_event:notify/2 or gen_event:sync_notify/2, this function is
%% called for each installed event handler to handle the event.
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_event(Event :: term(), State :: #state{}) ->
    {ok, NewState :: #state{}} |
    {ok, NewState :: #state{}, hibernate} |
    {swap_handler, Args1 :: term(), NewState :: #state{},
        Handler2 :: (atom() | {atom(), Id :: term()}), Args2 :: term()} |
    remove_handler).
handle_event(Event, State) ->
    case catch do_handle_event(Event, State) of
        {ok, NewState} ->
            {ok, NewState};
        Error ->
            lager:error("Client handle [~p] fail:~p", [Event, Error]),
            {ok, State}
    end.

do_handle_event({action_client, Type, Msg}, #state{
    connect_nodes = Connects
} = State) ->
    case Type == all of
        true ->
            rpc:abcast([Node || #node{node = Node} <- Connects], ?NODE_CLIENT, {client, Msg});
        false ->
            case lists:keyfind(Type, #node.type, Connects) of
                #node{node = Node} ->
                    rpc:abcast([Node], ?NODE_CLIENT, {client, Msg});
                _ ->
                    skip
            end
    end,
    {ok, State};
do_handle_event({connect, Type, Node, Cookie}, #state{
    connect_nodes = Connects
    ,reconnect_nodes = ReConnects
    ,reconnect_ref = OldTimer
} = State) ->
    case has_node(Node, Connects, ReConnects) of
        true ->
            {ok, State};
        false ->
            Record = #node{
                node = Node
                ,cookie = Cookie
                ,type = Type
            },
            case catch do_connect(Record) of
                true ->
                    {ok, State#state{
                        connect_nodes = [Record|Connects]
                    }};
                _ ->
                    NewTimer = set_timer(OldTimer),
                    {ok, State#state{
                        reconnect_nodes = [Record|ReConnects]
                        ,reconnect_ref = NewTimer
                    }}
            end
    end;
do_handle_event({disconnect, Type}, #state{
    connect_nodes = Nodes
    ,reconnect_nodes = ReConnects
    ,reconnect_ref = OldTimer
} = State) ->
    Fun = fun(#node{type = T}) -> T == Type end,
    case lists:partition(Fun, Nodes) of
        {[], _} ->
            {ok, State};
        {L, NewNodes} ->
            NewReConnects = do_disconnect(L, ReConnects),
            NewTimer = set_timer(OldTimer),
            {ok, State#state{
                connect_nodes = NewNodes
                ,reconnect_nodes = NewReConnects
                ,reconnect_ref = NewTimer
            }}
    end;
do_handle_event({del_connect, Type}, #state{
    connect_nodes = Nodes
    ,reconnect_nodes = ReConnects
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
                connect_nodes = NewNodes
                ,reconnect_nodes = NewReConnects
            }}
    end;
do_handle_event(_Event, State) ->
    {ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever an event manager receives a request sent using
%% gen_event:call/3,4, this function is called for the specified
%% event handler to handle the request.
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_call(Request :: term(), State :: #state{}) ->
    {ok, Reply :: term(), NewState :: #state{}} |
    {ok, Reply :: term(), NewState :: #state{}, hibernate} |
    {swap_handler, Reply :: term(), Args1 :: term(), NewState :: #state{},
        Handler2 :: (atom() | {atom(), Id :: term()}), Args2 :: term()} |
    {remove_handler, Reply :: term()}).
handle_call(Request, State) ->
    case catch do_handle_call(Request, State) of
        {ok, Reply, NewState} ->
            {ok, Reply, NewState};
        Error ->
            {ok, {error, Error}, State}
    end.

do_handle_call({call_client, Type, Msg}, #state{
    connect_nodes = Connects
} = State) ->
    Reply = case Type == all of
        true ->
            rpc:multi_server_call([Node || #node{node = Node} <- Connects], ?NODE_SERVER, {client, Msg});
        false ->
            case lists:keyfind(Type, #node.type, Connects) of
                #node{node = Node} ->
                    rpc:multi_server_call([Node], ?NODE_SERVER, {client, Msg});
                false ->
                    {[], []}
            end
    end,
    {ok, Reply, State};
do_handle_call({server_connect, Node}, #state{
    connect_nodes = Connects
} = State) ->
    Reply = case lists:keyfind(Node, #node.node, Connects) of
        #node{type = Type} ->
            gen_event:notify(?NODE_CLIENT, {server_connect, Type}),
            true;
        false ->
            false
    end,
    {ok, Reply, State};
do_handle_call(get_info, #state{
    connect_nodes = Connects
} = State) ->
    L = [Type || #node{type = Type} <- Connects],
    {ok, L, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called for each installed event handler when
%% an event manager receives any other message than an event or a
%% synchronous request (or a system message).
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_info(Info :: term(), State :: #state{}) ->
    {ok, NewState :: #state{}} |
    {ok, NewState :: #state{}, hibernate} |
    {swap_handler, Args1 :: term(), NewState :: #state{},
        Handler2 :: (atom() | {atom(), Id :: term()}), Args2 :: term()} |
    remove_handler).
handle_info({nodedown, Node}, #state{
    connect_nodes = Connects
    ,reconnect_nodes = ReConnects
    ,reconnect_ref = OldTimer
} = State) ->
    case lists:keytake(Node, #node.node, Connects) of
        {value, Record, NewConnects} ->
            NewTimer = set_timer(OldTimer),
            NewReConnects = [Record|ReConnects],
            gen_event:notify(?NODE_CLIENT, {server_nodedown, Record#node.type, Node}),
            {ok, State#state{
                connect_nodes = NewConnects
                ,reconnect_nodes = NewReConnects
                ,reconnect_ref = NewTimer
            }};
        _ ->
            {ok, State}
    end;
handle_info(reconnect, #state{
    connect_nodes = Connects
    ,reconnect_nodes = ReConnects
    ,reconnect_ref = OldTimer
} = State) ->
    {NewConnects, NewReConnects} = do_reconnect(ReConnects, Connects, []),
    NewTimer =
        case NewReConnects of
            [] ->
                undefined;
            _ ->
                set_timer(OldTimer)
        end,
    {ok, State#state{
        connect_nodes = NewConnects
        ,reconnect_nodes = NewReConnects
        ,reconnect_ref = NewTimer
    }};
handle_info({From, {server, Msg}}, State) ->
    Handlers = gen_event:which_handlers(?NODE_SERVER),
    Replys = [gen_event:call(?NODE_SERVER, Handler, Msg) || Handler <- Handlers],
    From ! {?NODE_SERVER, node(), Replys},
    {ok, State};
handle_info(_Info, State) ->
    {ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever an event handler is deleted from an event manager, this
%% function is called. It should be the opposite of Module:init/1 and
%% do any necessary cleaning up.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
-spec(terminate(Args :: (term() | {stop, Reason :: term()} | stop |
    remove_handler | {error, {'EXIT', Reason :: term()}} |
    {error, term()}), State :: term()) -> term()).
terminate(_Arg, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @end
%%--------------------------------------------------------------------
-spec(code_change(OldVsn :: term() | {down, term()}, State :: #state{},
    Extra :: term()) ->
    {ok, NewState :: #state{}}).
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
do_init([{Type, Node, Cookie}|T], Connect, ReConnect) ->
    case has_node(Node, Connect, ReConnect) of
        true ->
            do_init(T, Connect, ReConnect);
        false ->
            Record = #node{
                node = Node
                ,cookie = Cookie
                ,type = Type
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
        connect_nodes = Connect
        ,reconnect_nodes = []
    };
do_init([], Connect, ReConnect) ->
    #state{
        connect_nodes = Connect
        ,reconnect_nodes = ReConnect
        ,reconnect_ref = set_timer(undefined)
    }.

%% 连接节点
do_connect(#node{
    node = Node
    ,cookie = Cookie
}) ->
    erlang:set_cookie(Node, Cookie),
    case rpc:call(Node, node_server_base, check, []) of
        true ->
            erlang:monitor_node(Node, true);
        _ ->
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

set_timer(OldTimer) ->
    case erlang:is_reference(OldTimer) of
        true ->
            case erlang:read_timer(OldTimer) of
                N when is_integer(N) ->
                    OldTimer;
                _ ->
                    erlang:send_after(30000, self(), reconnect)
            end;
        false ->
            erlang:send_after(30000, self(), reconnect)
    end.

%% 节点是否已存在
has_node(Node, Connect, ReConnect) ->
    lists:keymember(Node, #node.node, Connect) orelse lists:keymember(Node, #node.node, ReConnect).
