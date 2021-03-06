-module(ts_command_registration_process).

-behaviour(gen_server).
-include("ts_command.hrl").
-include("ts_telnet.hrl").

%% API
-export([start_link/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).

-define(SERVER, ?MODULE). 

-record(state, {
	  application_process_PID_list=[]   ::[tuple()],
	  conf_file_prefix                  ::string()}).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link(ConfigurationFilePrefix) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [ConfigurationFilePrefix], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
init([ConfigurationFilePrefix]) ->    
    error_logger:info_msg("ts_command_registration_process (~w) has started with ConfigurationFilePrefix(~p) ~n", [self(), ConfigurationFilePrefix]),
    ets:new(commandTable,[set, named_table, {keypos, #node.nodeID}]),
    {ok, #state{conf_file_prefix=ConfigurationFilePrefix}, 0}.  % causes immediate timeout

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @spec handle_call(Request, From, State) ->
%%                                   {reply, Reply, State} |
%%                                   {reply, Reply, State, Timeout} |
%%                                   {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, Reply, State} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                  {noreply, State, Timeout} |
%%                                  {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_cast({register_application, ApplicationName, ApplRegistration_Fun}, #state{conf_file_prefix = ConfigurationFilePrefix}=State) ->
    error_logger:info_msg("Application ~p has been regsitered~n", [ApplicationName]),
    %% start the application process
    {ok, ApplicationProcessPID} = ts_application_loader:start_link( ConfigurationFilePrefix, ApplicationName, ApplRegistration_Fun),
    {noreply, State#state{application_process_PID_list = [{ApplicationName, ApplicationProcessPID} | State#state.application_process_PID_list]}};
handle_cast({unregister_application, ApplicationName, ApplUnregistration_Fun}, State) ->
    %% uninitialize the application and terminate the corresponding ts_application_loader instance
    {ApplicationName, ApplicationProcessPID} = lists:keyfind(ApplicationName, 1, State#state.application_process_PID_list),
    NewApplication_process_PID_list = lists:keydelete(ApplicationName, 1, State#state.application_process_PID_list),
    NewState = State#state{application_process_PID_list=NewApplication_process_PID_list},
    gen_server:cast(ApplicationProcessPID, {unregister_application, ?MODULE, ApplUnregistration_Fun}),
    {noreply, NewState};
handle_cast({install_node, NodeID, NodePropperties}, State) ->
    error_logger:info_msg("Received install_node: NodeID: ~p, NodePropperties: ~p~n", [NodeID,NodePropperties]),
    register_node(NodeID, NodePropperties),
    {noreply, State};
handle_cast({install_element, NodeIDList, CommandRecord}, State) ->
    error_logger:info_msg("Received install_element: NodeIDList: ~p, CommandRecord: ~p~n", [NodeIDList, CommandRecord]),
    register_element(NodeIDList, CommandRecord),
    {noreply, State};
handle_cast(_Msg, State) ->
    error_logger:info_msg("Received message: ~p, ~n", [_Msg]),
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_info(timeout, #state{conf_file_prefix = ConfigurationFilePrefix}=State) ->
    error_logger:info_msg("ConfigurationFilePrefix (~p)~n", [ConfigurationFilePrefix]),
    {noreply, State};
handle_info(_Info, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
register_node(NodeID, NodePropperties)->
    case ets:lookup(commandTable, NodeID) of
	[#node{nodeID = NodeID}] ->
	    error_logger:warning_msg("Warning!! ~ninstall_node(~w, ...). ~p has already been registered. ~nCommand will be ignored. ~n", [NodeID, NodePropperties]);
	[] ->
	    NodeTableID = ets:new(NodeID,[bag]),
	    Node = #node{
	      node_entry_fun =NodePropperties#node_propperties.node_entry_fun,
	      exec_mode =NodePropperties#node_propperties.exec_mode,
	      configuration_level =NodePropperties#node_propperties.configuration_level,
	      indention_level =NodePropperties#node_propperties.indention_level,
	      commandListTableID = NodeTableID,
	      nodeID = NodeID},
	    ets:insert(commandTable, Node),

	    %% Register exit command

	    Exit_fun = fun (VTY, _Command_param) ->
			       sr_command:vty_out(VTY, "%% Exiting... ~n", []),
			       cmd_exit
		       end,

	    Exit_cmd = #command{funcname= Exit_fun,
				cmdstr = ["exit"],
				helpstr = ["Exit command"]},

	    service_registration_lib:install_element([NodeID], Exit_cmd),


	    %% Register end command
	    Config_end_fun = fun (_VTY, _Command_param) ->
				     cmd_end
			     end,

	    Config_end_cmd =
		#command{funcname = Config_end_fun,
			 cmdstr = ["end"],
			 helpstr = ["End current mode and change to enable mode."]},

	    case NodeID of
		enable_node ->
		    ok; % Command not supported
		view_node ->
		    ok; % Command not supported
		_ ->
		    service_registration_lib:install_element([NodeID], Config_end_cmd)
	    end
    end.

register_element([], _NodeCommand) ->
    true;

register_element([NodeIDHead|NodeIDTail],NodeCommand) ->
    %%io:format("Node: ~w~n", [ets:lookup(commandTable, NodeIDHead)]),
    case ets:lookup(commandTable, NodeIDHead) of
	[ #node{commandListTableID =CommandTableID}] ->
	    ets:insert(CommandTableID, {NodeIDHead, NodeCommand});
	[] ->
	    io:format("Error!! ~ninstall_element([~p], ...). ~w has not been registered. ~nCommand will be ignored. ~n", [NodeIDHead, NodeIDHead])
    end,
    register_element(NodeIDTail, NodeCommand).


