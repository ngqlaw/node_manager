%%%-------------------------------------------------------------------
%% @doc node_manager top level supervisor.
%% @end
%%%-------------------------------------------------------------------

-module(node_manager_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).
-define(CHILD(Mod), {Mod, {Mod, start_link, []}, permanent, 5000, worker, [Mod]}).

%%====================================================================
%% API functions
%%====================================================================

start_link() ->
	supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%%====================================================================
%% Supervisor callbacks
%%====================================================================

%% Child :: {Id,StartFunc,Restart,Shutdown,Type,Modules}
init([]) ->
	Client = ?CHILD(node_client_base),
	Server = ?CHILD(node_server_base),
    Client = ?CHILD(mod_node_client),
    Server = ?CHILD(mod_node_server),
	Mange = ?CHILD(node_manager),
	{ok, { {one_for_one, 5, 60}, [Client, Server, Mange]} }.

%%====================================================================
%% Internal functions
%%====================================================================
