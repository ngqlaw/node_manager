%%%-------------------------------------------------------------------
%%% @author ngq <ngq_scut@126.com>
%%% @doc
%%%
%%% @end
%%% Created : 20. 一月 2017 16:02
%%%-------------------------------------------------------------------
-module(node_manager).
-author("ngq").

-behaviour(gen_server).

%% API
-export([
    start_link/0
    ,check_server/0
    ,check_client/1
    ,action_server/3
    ,action_server/4
    ,action_client/4
    ,call_server/3
    ,call_server/4
    ,call_client/4
    ,client_connect/3
    ,client_disconnect/1
    ,client_del_connect/1
    ,check_connect/1
    ,server_get_info/0
]).

%% gen_server callbacks
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3
]).

-define(SERVER, ?MODULE).
-define(APP, node_manager).

-record(state, {
    server
    ,server_handlers = []
    ,client
    ,client_handlers = []
}).

%%%===================================================================
%%% API
%%%===================================================================
%% @doc Starts the server
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% @doc 检查服务节点是否启动
check_server() ->
    check_pid(node_server_base).

%% @doc 检查客户节点是否启动
check_client(Node) ->
    case check_pid(node_client_base) of
        true ->
            gen_event:call(node_client_base, node_client_base, {'node_up', Node}),
            true;
        false ->
            false
    end.

check_pid(Atom) ->
    case erlang:whereis(Atom) of
        Pid when erlang:is_pid(Pid) ->
            erlang:is_process_alive(Pid);
        _ ->
            false
    end.

%% @doc 检查是否连上服务节点
check_connect(Type) ->
    L = gen_event:call(node_client_base, node_client_base, 'get_info'),
    lists:member(Type, L).

%% @doc 服务节点获取连接信息
server_get_info() ->
    gen_event:call(node_server_base, node_server_base, 'get_info').

%% @doc 执行
action_server(Module, Function, Args) ->
    gen_server:cast(?SERVER, {server, {action_server, all, Module, Function, Args}}).

action_server(Node, Module, Function, Args) ->
    gen_server:cast(?SERVER, {server, {action_server, Node, Module, Function, Args}}).

action_client(Type, Module, Function, Args) ->
    gen_server:cast(?SERVER, {client, {action_client, Type, Module, Function, Args}}).

%% @doc call调用
call_server(Module, Function, Args) ->
    gen_server:call(?SERVER, {server, {call_server, all, Module, Function, Args}}).

call_server(Node, Module, Function, Args) ->
    gen_server:call(?SERVER, {server, {call_server, Node, Module, Function, Args}}).

call_client(Type, Module, Function, Args) ->
    gen_server:call(?SERVER, {client, {call_client, Type, Module, Function, Args}}).

%% @doc 连接主节点
client_connect(Type, Node, Cookie) ->
    gen_server:cast(?SERVER, {connect, Type, Node, Cookie}).

%% @doc 断开连接
client_disconnect(Type) ->
    gen_server:cast(?SERVER, {disconnect, Type}).

%% @doc 移除连接
client_del_connect(Type) ->
    gen_server:cast(?SERVER, {del_connect, Type}).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
-spec(init(Args :: term()) ->
    {ok, State :: #state{}} | {ok, State :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term()} | ignore).
init([]) ->
    erlang:process_flag(priority, high),
    erlang:send_after(1000, self(), init),
    {ok, #state{}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_call(Request :: term(), From :: {pid(), Tag :: term()},
    State :: #state{}) ->
    {reply, Reply :: term(), NewState :: #state{}} |
    {reply, Reply :: term(), NewState :: #state{}, timeout() | hibernate} |
    {noreply, NewState :: #state{}} |
    {noreply, NewState :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term(), Reply :: term(), NewState :: #state{}} |
    {stop, Reason :: term(), NewState :: #state{}}).
handle_call(Request, From, State) ->
    case catch do_handle_call(Request, From, State) of
        noreply ->
            {noreply, State};
        {ok, Reply} ->
            {reply, Reply, State};
        Error ->
            lager:error("Node call[~p] fail:~p", [Request, Error]),
            {reply, {error, Error}, State}
    end.

do_handle_call({server, Message}, From, #state{
    server_handlers = Handlers
}) ->
    spawn_link(
        fun() ->
            Reply =
                case catch apply_server(Handlers, Message) of
                    {ok, Res} ->
                        Ref = erlang:make_ref(),
                        gen_event:notify(node_server_base, {Message, {self(), Ref}, Res}),
                        get_reply(Ref);
                    Error ->
                        lager:error("Apply server node call[~p] fail:~p", [Message, Error]),
                        {error, Error}
                end,
            gen_server:reply(From, Reply)
        end),
    noreply;
do_handle_call({client, Message}, From, #state{
    client_handlers = Handlers
}) ->
    spawn_link(
        fun() ->
            Reply =
                case catch apply_client(Handlers, Message) of
                    {ok, Res} ->
                        Ref = erlang:make_ref(),
                        gen_event:notify(node_client_base, {Message, {self(), Ref}, Res}),
                        get_reply(Ref);
                    Error ->
                        lager:error("Apply client node call[~p] fail:~p", [Message, Error]),
                        {error, Error}
                end,
            gen_server:reply(From, Reply)
        end),
    noreply.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_cast(Request :: term(), State :: #state{}) ->
    {noreply, NewState :: #state{}} |
    {noreply, NewState :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term(), NewState :: #state{}}).
handle_cast(Request, State) ->
    case catch do_handle_cast(Request, State) of
        ok ->
            ok;
        Error ->
            lager:error("Apply node cast[~p] fail:~p", [Request, Error])
    end,
    {noreply, State}.

do_handle_cast({server, Message}, #state{
    server_handlers = Handlers
}) ->
    case apply_server(Handlers, Message) of
        {ok, Res} ->
            gen_event:notify(node_server_base, {Message, Res});
        Error ->
            {error, Error}
    end;
do_handle_cast({client, Message}, #state{
    client_handlers = Handlers
}) ->
    case apply_client(Handlers, Message) of
        {ok, Res} ->
            gen_event:notify(node_client_base, {Message, Res});
        Error ->
            {error, Error}
    end;
do_handle_cast({connect, Type, Node, Cookie}, #state{}) ->
    gen_event:notify(node_client_base, {connect, Type, Node, Cookie}),
    ok;
do_handle_cast({disconnect, Type}, #state{}) ->
    gen_event:notify(node_client_base, {disconnect, Type}),
    ok;
do_handle_cast({del_connect, Type}, #state{}) ->
    gen_event:notify(node_client_base, {del_connect, Type}),
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
-spec(handle_info(Info :: timeout() | term(), State :: #state{}) ->
    {noreply, NewState :: #state{}} |
    {noreply, NewState :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term(), NewState :: #state{}}).
handle_info(init, #state{} = State) ->
    {ClientMonitorRef, ClientHandlers} = init_client(),
    {ServerMonitorRef, ServerHandlers} = init_server(),
    {noreply, State#state{
        client = ClientMonitorRef
        ,client_handlers = ClientHandlers
        ,server = ServerMonitorRef
        ,server_handlers = ServerHandlers
    }};
handle_info({'DOWN', MonitorRef, process, _Object, _Info}, #state{client = MonitorRef} = State) ->
    erlang:send_after(1000, self(), re_moiter_client),
    {noreply, State#state{client = undefined, client_handlers = []}};
handle_info({'DOWN', MonitorRef, process, _Object, _Info}, #state{server = MonitorRef} = State) ->
    erlang:send_after(1000, self(), re_moiter_server),
    {noreply, State#state{server = undefined, server_handlers = []}};
handle_info(re_moiter_client, #state{} = State) ->
    {ClientMonitorRef, ClientHandlers} = init_client(),
    {noreply, State#state{client = ClientMonitorRef, client_handlers = ClientHandlers}};
handle_info(re_moiter_server, #state{} = State) ->
    {ServerMonitorRef, ServerHandlers} = init_server(),
    {noreply, State#state{server = ServerMonitorRef, server_handlers = ServerHandlers}};
handle_info(_Info, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
-spec(terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()),
    State :: #state{}) -> term()).
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
-spec(code_change(OldVsn :: term() | {down, term()}, State :: #state{},
    Extra :: term()) ->
    {ok, NewState :: #state{}} | {error, Reason :: term()}).
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
%% 初始化客户节点
init_client() ->
    ClientMonitorRef = erlang:monitor(process, node_client_base),
    Done = gen_event:which_handlers(node_client_base),
    {ok, ClientHandlers} = application:get_env(?APP, client_ext_handle),
    Handles = [
        begin
            ok = node_client_base:add_handler(CHandler, []),
            CHandler
        end || CHandler <- ClientHandlers ++ [node_client_base], not lists:member(CHandler, Done)
    ],
    {ClientMonitorRef, Handles}.

%% 初始化服务节点
init_server() ->
    ServerMonitorRef = erlang:monitor(process, node_server_base),
    Done = gen_event:which_handlers(node_server_base),
    {ok, ServerHandlers} = application:get_env(?APP, server_ext_handle),
    Handles = [
        begin
            ok = node_server_base:add_handler(SHandler, []),
            SHandler
        end || SHandler <- ServerHandlers ++ [node_server_base], not lists:member(SHandler, Done)
    ],
    {ServerMonitorRef, Handles}.

%% 服务节点执行请求
apply_server(Handlers, Message) ->
    Ref = erlang:make_ref(),
    gen_event:notify(node_server_base, {gather, self(), Ref, Message}),
    case gather_loop(Ref, Handlers, []) of
        timeout ->
            timeout;
        unknown ->
            unknown;
        Res ->
            {ok, Res}
    end.

%% 服务节点执行请求
apply_client(Handlers, Message) ->
    Ref = erlang:make_ref(),
    gen_event:notify(node_client_base, {gather, self(), Ref, Message}),
    case gather_loop(Ref, Handlers, []) of
        timeout ->
            timeout;
        unknown ->
            unknown;
        Res ->
            {ok, Res}
    end.

%% 收集执行需求信息
gather_loop(_Ref, [], Res) ->
    Res;
gather_loop(Ref, Handlers, Res) ->
    receive
        {Ref, Handler, Reply} ->
            case lists:member(Handler, Handlers) of
                true ->
                    gather_loop(Ref, lists:delete(Handler, Handlers), [{Handler, Reply}|Res]);
                false ->
                    unknown
            end
    after 5000 ->
        timeout
    end.

%% 等待请求返回
get_reply(Ref) ->
    receive
        {Ref, Reply} ->
            Reply
    after 5000 ->
        {error, timeout}
    end.
