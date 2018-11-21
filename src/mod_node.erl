%%%-------------------------------------------------------------------
%%% @author ngq <ngq_scut@126.com>
%%% @doc
%%%
%%% @end
%%% Created : 20. 一月 2017 13:55
%%%-------------------------------------------------------------------
-module(mod_node).
-author("ngq").

-behaviour(gen_event).

%% API
-export([start_link/0,
    add_handler/0]).

%% gen_event callbacks
-export([init/1,
    handle_event/2,
    handle_call/2,
    handle_info/2,
    terminate/2,
    code_change/3]).

-define(SERVER, ?MODULE).

-record(state, {}).

%%%===================================================================
%%% gen_event callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Creates an event manager
%%
%% @end
%%--------------------------------------------------------------------
-spec(start_link() -> {ok, pid()} | {error, {already_started, pid()}}).
start_link() ->
    gen_event:start_link({local, ?SERVER}).

%%--------------------------------------------------------------------
%% @doc
%% Adds an event handler
%%
%% @end
%%--------------------------------------------------------------------
-spec(add_handler() -> ok | {'EXIT', Reason :: term()} | term()).
add_handler() ->
    gen_event:add_handler(?SERVER, ?MODULE, []).

%%%===================================================================
%%% gen_event callbacks
%%%===================================================================
init([]) ->
    {ok, #state{}}.

handle_event(Event, State) ->
    case catch do_handle_event(Event, State) of
        {ok, NewState} ->
            {ok, NewState};
        _Error ->
%%            lager:error("Node handle event[~p] fail:~p", [Event, Error]),
            {ok, State}
    end.

do_handle_event({gather, ParentPid, Ref, _Message}, #state{} = State) ->
    ParentPid ! {Ref, ?MODULE, []},
    {ok, State};
do_handle_event({{call_client, Type, Module, Function, Args}, {ParentPid, Ref}, Res}, #state{} = State) ->
    case action(Type, Res, reply, Module, Function, Args) of
        {ok, Reply} ->
            ParentPid ! {Ref, Reply},
            ok;
        Error ->
%%            lager:error("Node call apply[~p:~p:~p] fail:~p", [Module, Function, Args, Error]),
            ParentPid ! {Ref, Error},
            skip
    end,
    {ok, State};
do_handle_event({{action_client, Type, Module, Function, Args}, Res}, #state{} = State) ->
    case action(Type, Res, noreply, Module, Function, Args) of
        {ok, _Reply} ->
            ok;
        _Error ->
%%            lager:error("Node action apply[~p:~p:~p] fail:~p", [Module, Function, Args, Error]),
            skip
    end,
    {ok, State};
do_handle_event({nodedown, _Type, _Node}, #state{} = State) ->
    {ok, State};
do_handle_event({'node_up', _Type}, #state{} = State) ->
    {ok, State};
do_handle_event(_Event, #state{} = State) ->
    {ok, State}.

handle_call(_Request, State) ->
    Reply = ok,
    {ok, Reply, State}.

handle_info(_Info, State) ->
    {ok, State}.

terminate(_Arg, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
action(Type, Res, CallBack, Module, Function, Args) ->
    case lists:keyfind(node_client_base, 1, Res) of
        {_, L} ->
            ActionList =
                case Type == all of
                    true ->
                        [Node || {_, Node} <- L];
                    false ->
                        [Node || {T, Node} <- L, T == Type]
                end,
            do_action(ActionList, CallBack, Module, Function, Args);
        _ ->
            not_exist
    end.

do_action(Nodes, noreply, Module, Function, Args) ->
    Reply = [rpc:cast(Node, Module, Function, Args) || Node <- Nodes],
    {ok, Reply};
do_action(Nodes, reply, Module, Function, Args) ->
    Pid = self(),
    spawn_link(
        fun() ->
            Reply = call_action(Nodes, 1, Module, Function, Args, []),
            Pid ! {ok, Reply},
            ok
        end
    ),
    receive
        {ok, Res} -> {ok, Res}
    after 5000 -> timeout
    end.

call_action([Node|T], N, Module, Function, Args, Res) ->
    case (N rem 50) == 0 of
        true ->
            timer:sleep(100);
        false ->
            skip
    end,
    Reply = rpc:call(Node, Module, Function, Args),
    call_action(T, N + 1, Module, Function, Args, [Reply|Res]);
call_action([], _N, _Module, _Function, _Args, Res) ->
    Res.
