-ifndef(NODE_MANAGER_H).
-define(NODE_MANAGER_H, true).

-define(NODE_APP, node_manager).

%% 节点信息
-record(node, {
    node,       % 节点
    cookie      % 节点cookie
}).

-ifndef(INFO).
-define(INFO(Format), error_logger:info_msg(Format)).
-define(INFO(Format, Args), error_logger:info_msg(Format, Args)).
-endif.

-ifndef(ERROR).
-define(ERROR(Format), error_logger:error_msg(Format)).
-define(ERROR(Format, Args), error_logger:error_msg(Format, Args)).
-endif.

-endif.