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

%% API
-export([
    start_link/0,
    add_handler/2
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

-define(SERVER, ?MODULE).

-record(state, {
    connect_nodes = []     %% 连接中的节点
}).

%%%===================================================================
%%% gen_event callbacks
%%%===================================================================
%% @doc Creates an event manager
start_link() ->
    gen_event:start_link({local, ?SERVER}).

%% @doc Adds an event handler
add_handler(Handler, Args) ->
    gen_event:add_handler(?SERVER, Handler, Args).

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
    ok = net_kernel:monitor_nodes(true, [{node_type, hidden}, nodedown_reason]),
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
        _Error ->
            {ok, State}
    end.

do_handle_event({gather, ParentPid, Ref, _Message}, #state{
    connect_nodes = Connects
} = State) ->
    ParentPid ! {Ref, ?MODULE, Connects},
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
        _Error ->
            {ok, ok, State}
    end.

do_handle_call('get_info', #state{
    connect_nodes = Connects
} = State) ->
    {ok, Connects, State}.

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
    case rpc:call(Node, node_manager, check_client, [node()]) of
        true ->
            gen_event:notify(?SERVER, {nodeup, Node}),
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
            gen_event:notify(?SERVER, {nodedown, Node}),
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
