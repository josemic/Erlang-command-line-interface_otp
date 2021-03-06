-module(service_registration_lib).
-export([start/2, stop/2, install_node/2, install_element/2, vty_out/2, vty_out/3]).

-include("../../tcp_connection/src/tcp_connection.hrl").

start(ApplicationName, ApplRegistration_Fun)->
    gen_server:cast(ts_command_registration_process, {register_application, ApplicationName, ApplRegistration_Fun}).

stop(ApplicationName, ApplUnregistration_Fun)-> 
    gen_server:cast(ts_command_registration_process, {unregister_application, ApplicationName, ApplUnregistration_Fun}).


install_node(NodeID, NodePropperties)->
    gen_server:cast(ts_command_registration_process, {install_node, NodeID, NodePropperties}).

install_element(NodeIDList, CommandRecord)->
    gen_server:cast(ts_command_registration_process, {install_element, NodeIDList, CommandRecord}).

vty_out(VTY, String) ->
    vty_out(VTY, String,[]).

vty_out(VTY, StringWithCR, List) ->
    %% Substitute all ?CR with ?CR ?LF for telnet
    FormattedStringWithCR = io_lib:format(StringWithCR, List),
    case VTY of
	{vty, VTY_PID} ->
	    FormattedStringWithCRLF = re:replace(FormattedStringWithCR,binary_to_list(<<?LF>>),binary_to_list(<<?CR>>) ++ binary_to_list(<<?LF>>),[global, {return, list}]), 
	    %%VTY_PID ! {output, FormattedStringWithCRLF};
	    gen_server:cast(VTY_PID, {output, FormattedStringWithCRLF});
	{vty_socket, VTY_Socket} ->
	    FormattedStringWithCRLF = re:replace(FormattedStringWithCR,binary_to_list(<<?LF>>),binary_to_list(<<?CR>>) ++ binary_to_list(<<?LF>>),[global, {return, list}]), 
            gen_tcp:send(VTY_Socket, [FormattedStringWithCRLF]);
	vty_direct ->
	    io:format(FormattedStringWithCR);
	{file, IoDevice} ->
	    file:write(IoDevice, FormattedStringWithCR)
    end.

