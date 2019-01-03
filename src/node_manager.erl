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

-include("node_manager.hrl").

%% API
-export([
    start_link/0,
    start/0,
    is_connect/1,
    server_info/0,
    action_server/1, action_server/2,
    call_server/1, call_server/2,
    action_client/2,
    call_client/2,
    client_connect/3,
    client_disconnect/1,
    client_del_connect/1
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

-record(state, {
    server,
    server_handlers = [],
    client,
    client_handlers = []
}).

%%%===================================================================
%%% API
%%%===================================================================
%% @doc Starts the server
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

start() ->
    gen_server:cast(?SERVER, init).

%% @doc 检查是否连上服务节点
is_connect(Type) ->
    L = gen_event:call(?NODE_CLIENT, node_client_base, get_info),
    lists:member(Type, L).

%% @doc 服务节点获取连接信息
server_info() ->
    gen_event:call(?NODE_SERVER, node_server_base, get_info).

%% @doc 服务节点执行
-spec(action_server(Msg :: term()) -> ok).
action_server(Msg) ->
    action_server(all, Msg).

action_server(Node, Msg) ->
    gen_event:notify(?NODE_SERVER, {action_server, Node, Msg}).

%% @doc 服务节点call调用
-spec(call_server(Msg :: term()) -> {Replys :: list(), BadNodes :: list()}).
call_server(Msg) ->
    call_server(all, Msg).

call_server(Node, Msg) ->
    gen_event:call(?NODE_SERVER, node_server_base, {call_server, Node, Msg}).

%% @doc 客户节点执行
action_client(Type, Msg) ->
    gen_event:notify(?NODE_CLIENT, {action_client, Type, Msg}).

%% @doc 客户节点call调用
call_client(Type, Msg) ->
    gen_event:call(?NODE_CLIENT, node_client_base, {call_client, Type, Msg}).

%% @doc 连接主节点
client_connect(Type, Node, Cookie) ->
    gen_event:notify(?NODE_CLIENT, {connect, Type, Node, Cookie}).

%% @doc 断开连接
client_disconnect(Type) ->
    gen_event:notify(?NODE_CLIENT, {disconnect, Type}).

%% @doc 移除连接
client_del_connect(Type) ->
    gen_event:notify(?NODE_CLIENT, {del_connect, Type}).

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
handle_call(_Request, _From, State) ->
    {reply, undefined, State}.

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
handle_cast(init, #state{} = State) ->
    {ClientMonitorRef, ClientHandlers} = node_client_base:start_handler(),
    {ServerMonitorRef, ServerHandlers} = node_server_base:start_handler(),
    {noreply, State#state{
        client = ClientMonitorRef,
        client_handlers = ClientHandlers,
        server = ServerMonitorRef,
        server_handlers = ServerHandlers
    }};
handle_cast(_Request, State) ->
    {noreply, State}.

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
handle_info({'DOWN', MonitorRef, process, _Object, _Info}, #state{client = MonitorRef} = State) ->
    erlang:send_after(1000, self(), re_moiter_client),
    {noreply, State#state{client = undefined, client_handlers = []}};
handle_info({'DOWN', MonitorRef, process, _Object, _Info}, #state{server = MonitorRef} = State) ->
    erlang:send_after(1000, self(), re_moiter_server),
    {noreply, State#state{server = undefined, server_handlers = []}};
handle_info(re_moiter_client, #state{} = State) ->
    {ClientMonitorRef, ClientHandlers} = node_client_base:start_handler(),
    {noreply, State#state{client = ClientMonitorRef, client_handlers = ClientHandlers}};
handle_info(re_moiter_server, #state{} = State) ->
    {ServerMonitorRef, ServerHandlers} = node_server_base:start_handler(),
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
