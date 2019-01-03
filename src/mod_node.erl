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

%% gen_event callbacks
-export([
    init/1,
    handle_event/2,
    handle_call/2,
    handle_info/2,
    terminate/2,
    code_change/3
]).

-record(state, {}).

%%%===================================================================
%%% gen_event callbacks
%%%===================================================================
init([]) ->
    {ok, #state{}}.

handle_event(Event, State) ->
    case catch do_handle_event(Event, State) of
        {ok, NewState} ->
            {ok, NewState};
        Error ->
            lager:error("Node handle event[~p] fail:~p", [Event, Error]),
            {ok, State}
    end.

%% 客户节点连接信号
do_handle_event({client_connect, Node}, #state{} = State) ->
    lager:debug("Client Node connect:~p", [Node]),
    {ok, State};
%% 客户节点断开信号
do_handle_event({client_nodedown, Node}, #state{} = State) ->
    lager:debug("Client Node down:~p", [Node]),
    {ok, State};
%% 服务节点连接信号
do_handle_event({server_connect, Type}, #state{} = State) ->
    lager:debug("Server connect:~p", [Type]),
    {ok, State};
%% 服务节点断开信号
do_handle_event({server_nodedown, Type, Node}, #state{} = State) ->
    lager:debug("Server down:~p ~p", [Type, Node]),
    {ok, State};
do_handle_event(Event, #state{} = State) ->
    lager:debug("Unknow event:~p", [Event]),
    {ok, State}.

handle_call(Request, State) ->
    lager:debug("Call event:~p", [Request]),
    Reply = ok,
    {ok, Reply, State}.

handle_info(Info, State) ->
    lager:debug("Info event:~p", [Info]),
    {ok, State}.

terminate(_Arg, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
