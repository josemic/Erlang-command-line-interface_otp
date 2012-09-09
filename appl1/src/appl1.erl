%%%-------------------------------------------------------------------
%%% @author michael <michael@michael-desktop>
%%% @copyright (C) 2012, michael
%%% @doc
%%%
%%% @end
%%% Created :  3 Sep 2012 by michael <michael@michael-desktop>
%%%-------------------------------------------------------------------
-module(appl1).
-include("../../tcp_connection/src/ts_command.hrl").

-export([start/0, stop/0]).

start()->
    ApplRegistration_Fun = fun () ->
				   error_logger:info_msg("Application ~p has been regsitered~n", [?MODULE_STRING]),    
				   %% register the server_data_table table to store terminal common data
				   ets:new(server_data_table,[ordered_set, named_table, public]),
				   %% preinitialize the hostname, it may get overloader from config-file
				   ets:insert(server_data_table, {hostname, "ErlangCLI"}),
				   ok
			   end,
    service_registration_lib:start(?MODULE_STRING, ApplRegistration_Fun),
    install_all().

stop()-> 
    ApplUnregistration_Fun = fun () ->
				     error_logger:info_msg("Application ~p has been unregsitered~n", [?MODULE_STRING]),
				     %% delete the server_data_table
				     ets:delete(server_data_table),
				     ok
			     end,
    service_registration_lib:stop(?MODULE_STRING, ApplUnregistration_Fun).

install_all()->
    Enable_fun =  fun (_VTY, _Command_param) ->
			  cmd_enable
		  end,

    Enable_cmd = #command{funcname= Enable_fun,
			  cmdstr  = ["enable"],
			  helpstr = ["Enable command"]},

    Disable_fun =  fun (_VTY, _Command_param) ->
			   cmd_disable
		   end,

    Disable_cmd = #command{funcname= Disable_fun,
			   cmdstr  = ["disable"],
			   helpstr = ["Disable command"]},


    service_registration_lib:install_node(enable_node, 
					  #node_propperties{node_entry_fun = undefined,
							    exec_mode = privileged,
							    configuration_level = undefined}),
    service_registration_lib:install_node(view_node, 
					  #node_propperties{node_entry_fun = undefined,
							    exec_mode = user,
							    configuration_level= undefined}),

    sr_command:install_default(enable_node),
    sr_command:install_default(view_node),

    service_registration_lib:install_element([enable_node], Disable_cmd),
    service_registration_lib:install_element([view_node], Enable_cmd),

    %% Install the other nodes:
    sr_config:install(),
    sr_gsmnet:install(), 
    sr_demo:install(). % demo node is within gsmnet_node
