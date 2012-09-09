-module(ts_root_sup).

-behaviour(supervisor).
-define (DEFAULT_CONFIGURATION_FILENAME_PREFIX, "Configuration").
%% API
-export([start_link/0, 
	 start_connection_worker/2]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

%%%===================================================================
%%% API functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the supervisor
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

start_connection_worker(Socket, Instance) ->
    Instance_s = integer_to_list(Instance),
    Ref_s = erlang:ref_to_list(make_ref()),                       
    %% Ref_s makes the instance unique after restart
    %% as instance starts again at 0
    Name_s = ?MODULE_STRING ++ "_" ++ Instance_s  ++ "_" ++ Ref_s,  
    Name = list_to_atom (Name_s),
    %% the name must be a unique atom
    TCP_connection_worker = {Name, {tcp_connection, start_link, [Socket, Instance]},
    			  temporary, 2000, worker, [tcp_connection]},
    supervisor:start_child(?SERVER, TCP_connection_worker).

%%%===================================================================
%%% Supervisor callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever a supervisor is started using supervisor:start_link/[2,3],
%% this function is called by the new process to find out about
%% restart strategy, maximum restart frequency and child
%% specifications.
%%
%% @spec init(Args) -> {ok, {SupFlags, [ChildSpec]}} |
%%                     ignore |
%%                     {error, Reason}
%% @end
%%--------------------------------------------------------------------
init([]) ->
    ConfigurationFilePrefix = case application:get_env(tcp_server, conf_file) of
	       {ok, C} -> C;
	       undefined -> ?DEFAULT_CONFIGURATION_FILENAME_PREFIX
	   end,
    RestartStrategy = one_for_one,
    MaxRestarts = 10,
    MaxSecondsBetweenRestarts = 60,

    SupFlags = {RestartStrategy, MaxRestarts, MaxSecondsBetweenRestarts},

    TCP_connector = {tcp_connector, {tcp_connector, start_link, []},
		     permanent, brutal_kill, worker, [tcp_connector]},
    TS_command_registration_process = {ts_command_registration_process, {ts_command_registration_process, start_link, [ConfigurationFilePrefix]},
		     temporary, brutal_kill, worker, [ts_command_registration_process]},
    {ok, {SupFlags, [TCP_connector, TS_command_registration_process]}}.
%%%===================================================================
%%% Internal functions
%%%===================================================================
