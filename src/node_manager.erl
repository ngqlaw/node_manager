%%%-------------------------------------------------------------------
%%% @author ngq <ngq_scut@126.com>
%%% @doc
%%%
%%% @end
%%% Created : 20. 一月 2017 16:02
%%%-------------------------------------------------------------------
-module(node_manager).
-author("ngq").

-include("node_manager.hrl").

%% API
-export([
    start/0,
    client_info/0,
    server_info/0,
    action_server/1, action_server/2,
    call_server/1, call_server/2,
    action_client/1, action_client/2,
    call_client/1, call_client/2,
    client_connect/3,
    client_disconnect/1
]).

-type reply() :: {list(), list()} | list() | term().

%%%===================================================================
%%% API
%%%===================================================================

%% @doc 启动
start() ->
    % 客户端
    ClientHandlers = application:get_env(?NODE_APP, client_ext_handle, []),
    mod_node_client:start_handler(ClientHandlers),
    % 服务端
    ServerHandlers = application:get_env(?NODE_APP, server_ext_handle, []),
    mod_node_server:start_handler(ServerHandlers),
    ok.

%% @doc 客戶节点信息
client_info() ->
    gen_server:call(?NODE_CLIENT, get_info).

%% @doc 服务节点信息
server_info() ->
    gen_server:call(?NODE_SERVER, get_info).

%% @doc 服务节点异步执行
-spec(action_server(Msg :: term()) -> ok).
action_server(Msg) ->
    action_server(all, Msg).
action_server(Node, Msg) ->
    node_server_base:remote_action(Node, Msg).

%% @doc 服务节点同步调用
-spec(call_server(Msg :: term()) -> reply()).
call_server(Msg) ->
    call_server(all, Msg).
call_server(Node, Msg) ->
    node_server_base:remote_call(Node, Msg).

%% @doc 客户节点异步执行
-spec(action_client(Msg :: term()) -> ok).
action_client(Msg) ->
    action_client(all, Msg).
action_client(Type, Msg) ->
    gen_event:notify(?NODE_CLIENT, {action_client, Type, Msg}).

%% @doc 客户节点同步调用
-spec(call_client(Msg :: term()) -> reply()).
call_client(Msg) ->
    call_client(all, Msg).
call_client(Type, Msg) ->
    gen_event:call(?NODE_CLIENT, node_client_base, {call_client, Type, Msg}).

%% @doc 连接主节点
client_connect(Type, Node, Cookie) ->
    gen_server:cast(?NODE_CLIENT, {connect, Type, Node, Cookie}).

%% @doc 移除连接
client_disconnect(Type) ->
    gen_server:cast(?NODE_CLIENT, {disconnect, Type}).

%%%===================================================================
%%% Internal functions
%%%===================================================================
