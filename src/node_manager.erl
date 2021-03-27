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
    clients/0,
    servers/0
]).

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
-spec(clients() -> Nodes :: [atom()]).
clients() ->
    gen_server:call(node_server_base, get_info).

%% @doc 服务节点信息
-spec(servers() -> NodeInfo :: [#node{}]).
servers() ->
    gen_server:call(node_client_base, get_info).

%%%===================================================================
%%% Internal functions
%%%===================================================================
