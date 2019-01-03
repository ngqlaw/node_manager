%%%-------------------------------------------------------------------
%%% @author ngq <ngq_scut@126.com>
%%% @doc
%%%
%%% @end
%%% Created : 19. 一月 2017 16:01
%%%-------------------------------------------------------------------
-module(node_server_base).
-author("ngq").

-behaviour(gen_event).

-include("node_manager.hrl").

%% API
-export([
    start_link/0,
    add_handler/2,
    start_handler/0,
    check/0
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
    connect_nodes = []     %% 连接中的节点
}).

%%%===================================================================
%%% gen_event callbacks
%%%===================================================================
%% @doc Creates an event manager
start_link() ->
    gen_event:start_link({local, ?NODE_SERVER}).

%% @doc Adds an event handler
add_handler(Handler, Args) ->
    gen_event:add_handler(?NODE_SERVER, Handler, Args).

%% @doc 初始化服务节点
start_handler() ->
    ServerMonitorRef = erlang:monitor(process, ?NODE_SERVER),
    Done = gen_event:which_handlers(?NODE_SERVER),
    {ok, ServerHandlers} = application:get_env(?NODE_APP, server_ext_handle),
    Handles = [
        begin
            ok = add_handler(SHandler, []),
            SHandler
        end || SHandler <- ServerHandlers ++ [?MODULE], not lists:member(SHandler, Done)
    ],
    {ServerMonitorRef, Handles}.

%% @doc 检查服务节点是否启动
check() ->
    case erlang:whereis(?NODE_SERVER) of
        Pid when erlang:is_pid(Pid) ->
            erlang:is_process_alive(Pid);
        _ ->
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
    Type = case application:get_env(?NODE_APP, client_type, all) of
        visible -> visible;
        hidden -> hidden;
        _ -> all
    end,
    ok = net_kernel:monitor_nodes(true, [{node_type, Type}, nodedown_reason]),
    {ok, #state{
        connect_nodes = []
    }}.

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
            lager:error("Server handle [~p] fail:~p", [Event, Error]),
            {ok, State}
    end.

do_handle_event({action_server, Node, Msg}, #state{
    connect_nodes = Connects
} = State) ->
    case Node == all of
        true ->
            rpc:abcast(Connects, ?NODE_CLIENT, Msg);
        false ->
            case lists:member(Node, Connects) of
                true ->
                    rpc:abcast([Node], ?NODE_CLIENT, Msg);
                false ->
                    skip
            end
    end,
    {ok, State};
do_handle_event(_Event, #state{} = State) ->
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

do_handle_call({call_server, Node, Msg}, #state{
    connect_nodes = Connects
} = State) ->
    Reply = case Node == all of
        true ->
            rpc:multi_server_call(Connects, ?NODE_CLIENT, Msg);
        false ->
            case lists:member(Node, Connects) of
                true ->
                    rpc:multi_server_call([Node], ?NODE_CLIENT, Msg);
                false ->
                    {[], []}
            end
    end,
    {ok, Reply, State};
do_handle_call(get_info, #state{
    connect_nodes = Connects
} = State) ->
    {ok, Connects, State};
do_handle_call({From, Msg}, State) ->
    Handlers = gen_event:which_handlers(?NODE_SERVER),
    Replys = [gen_event:call(?NODE_SERVER, Handler, Msg) || Handler <- Handlers],
    From ! {?NODE_SERVER, node(), Replys},
    {ok, State}.

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
handle_info({nodeup, Node, _InfoList}, #state{
    connect_nodes = Connects
} = State) ->
    case rpc:call(Node, node_client_base, check, [node()]) of
        true ->
            gen_event:notify(?NODE_SERVER, {client_connect, Node}),
            {ok, State#state{
                connect_nodes = [Node|Connects]
            }};
        _ ->
            {ok, State}
    end;
handle_info({nodedown, Node, _InfoList}, #state{
    connect_nodes = Connects
} = State) ->
    case lists:member(Node, Connects) of
        true ->
            gen_event:notify(?NODE_SERVER, {client_nodedown, Node}),
            {ok, State#state{
                connect_nodes = lists:delete(Node, Connects)
            }};
        false ->
            {ok, State}
    end;
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
