-module(sr_config).
-export([install/0]).
-include("../../tcp_connection/src/ts_command.hrl").
install()->

    Cfg_config_fun = fun(_VTY, _Command_param)-> 
			   %% enter config_node
			   {cmd_enter_node, config_node} 
		   end,

    Cfg_config_cmd = #command{ funcname= Cfg_config_fun, 
			     cmdstr  = ["configure","terminal"],
			     helpstr = ["Configuration from vty interface", 
					"Configuration terminal"]},

    Hostname_fun =  fun (VTY, Command_param) ->
			    [Hostname] = Command_param#command_param.str_list,
			    ets:insert(server_data_table, {hostname,  Hostname}),
			    service_registration_lib:vty_out(VTY, "%% Set hostname: ~p~n", [Hostname]),
			    cmd_success
		    end,

    Hostname_cmd = 
	#command{funcname = Hostname_fun,
		 cmdstr   = ["hostname", "WORD"],
		 helpstr  = ["Set system's network name",
			     "This system's network name"]},


    service_registration_lib:install_node(config_node, 
					#node_propperties{node_entry_fun = undefined,
							  exec_mode = privileged,
							  configuration_level = "config"}),

    sr_command:install_default(config_node),
    %% Enter config_node
    service_registration_lib:install_element([enable_node], Cfg_config_cmd),
    service_registration_lib:install_element([config_node], Hostname_cmd).

