-ifndef(NODE_MANAGER_H).
-define(NODE_MANAGER_H, true).

-define(NODE_APP, node_manager).

%% 客户端API进程
-define(NODE_CLIENT, node_client_base).
%% 服务端API进程
-define(NODE_SERVER, node_server_base).

%% 节点信息
-record(node, {
    node,       % 节点
    type,       % 别称
    cookie      % 节点cookie
}).

-endif.