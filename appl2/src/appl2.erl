%%%-------------------------------------------------------------------
%%% @author michael <michael@michael-desktop>
%%% @copyright (C) 2012, michael
%%% @doc
%%%
%%% @end
%%% Created :  3 Sep 2012 by michael <michael@michael-desktop>
%%%-------------------------------------------------------------------
-module(appl2).

-export([start/0, stop/0]).

start()->
    ApplRegistration_Fun = fun () ->
				   error_logger:info_msg("Application ~p has been regsitered~n", [?MODULE_STRING]),
				   cmd_success
			   end,

    gen_server:cast(ts_command_registration_process, {register_application, ?MODULE_STRING, ApplRegistration_Fun}).

stop()-> 
    ApplUnregistration_Fun = fun () ->
				     error_logger:info_msg("Application ~p has been unregsitered~n", [?MODULE_STRING]),
				     cmd_success
			     end,
    gen_server:cast(ts_command_registration_process, {unregister_application, ?MODULE_STRING, ApplUnregistration_Fun}).
