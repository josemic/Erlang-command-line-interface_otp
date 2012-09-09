-module(tcp_connection).

-include("tcp_connection.hrl").
-include("ts_command.hrl").
-include("ts_telnet.hrl").

-behaviour(gen_server).

%% API
-export([start_link/2]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).

-define(SERVER, ?MODULE). 

-record(state, { command_buffer_bin ::binary(),
		 configuration_path     ,% queue_new() set during initialization
		 conf_file                ::string(),
		 history_buffer          ,% queue_new() set during initialization
		 history_depth = 100     ::integer(),
		 history_index = 0       ::integer(),
		 index= []               ::[[integer()]],
		 insertion_mode = insert ::insert|delete,
		 instance                 ::integer(),
		 node = view_node         ::atom(),
		 position = 0             ::integer(),
		 print_process_PID        ::pid(), 
		 socket                   ::port(), 
		 window_width =  24       ::integer(), 
		 window_height = 80       ::integer()}).

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
start_link(Socket, Instance) when is_integer(Instance)->   
    Instance_s = integer_to_list(Instance),
    Ref_s = erlang:ref_to_list(make_ref()),
    Name_s = ?MODULE_STRING ++ "_" ++ Instance_s ++ "_" ++ Ref_s,
    Name = list_to_atom (Name_s),      
    error_logger:info_report("gen_server:start_link(~p)~n",[[{local, Name},?MODULE,[Socket],[],self()]]), 
    %% Name may be left away.
    %% gen_server:start_link(?MODULE,[Socket, ConfigurationFile],[]).
    gen_server:start_link({local, Name},?MODULE,[Socket, Instance],[]).


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
init([Socket, Instance]) ->
    error_logger:info_msg("tcp_connection has started (~w) on Socket (~w)~n", [self(),Socket]),
    {ok, #state{configuration_path = queue_new(),command_buffer_bin = <<>>, history_buffer = queue_new(),instance = Instance, position = 0, socket=Socket}, 0}.  % causes immediate timeout


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
    error_logger:info_msg("tcp_connection (~w) received unhandled call message (~w) ~n", [self(), _Request]),
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
handle_cast(stop, State) ->
    error_logger:info_msg("tcp_connection (~w) has been stopped ~n", [self()]),
    {stop, normal, State};
handle_cast(_Msg, State) ->   
    error_logger:info_msg("tcp_connection (~w) received unhandled cast message (~w) ~n", [self(), _Msg]),
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
handle_info(timeout, #state{instance = Instance, socket=Socket}=State) ->
						% configure telnet client
    gen_tcp:send(Socket, <<?IAC, ?WILL, ?ECHO>>),
    gen_tcp:send(Socket, <<?IAC, ?WILL, ?SUPPRESS_GO_AHEAD>>),
    gen_tcp:send(Socket, <<?IAC, ?DONT, ?LINE_MODE>>),
    gen_tcp:send(Socket, <<?IAC, ?DO, ?WINDOW_SIZE>>), % Do window size negotiation
    gen_tcp:send(Socket,<<?CR, ?LF>>),
    gen_tcp:send(Socket,
		 <<"Welcome to Erlang commandline interface.", ?LF,?CR,
		   "Copyright(C) 2012 Michael Josenhans", ?LF,?CR,
		   "License AGPL v3+: GNU AGPL version 3 or later <http://www.gnu.org/licenses/agpl-3.0.html>", ?LF, ?CR,
		   ?LF,?CR,
		   "This is free software: you are free to change and redistribute it.", ?LF,?CR,
		   "There is NO WARRANTY, to the extent permitted by law.", ?LF,?CR>>),
    gen_tcp:send(Socket,get_prompt(State)),
    {ok, PrintProcessPID} = ts_connection_print_process:start_link([Socket, Instance]),
    {noreply, State#state{print_process_PID = PrintProcessPID}};

handle_info({tcp, Socket, BytesBin}, #state{command_buffer_bin = CommandBufferBin, print_process_PID = PrintProcessPID, socket=Socket}=State) ->
    error_logger:info_msg("Socket (~p)~n", [Socket]),
    error_logger:info_msg("Received: ~p~n", [BytesBin]),
    {BytesFilteredBin, FilteredState} = filter_negotiation_messages(BytesBin, <<>>, State),
    error_logger:info_msg("Received and filtered: ~p~n", [BytesFilteredBin]),
    %% FilteredState2 = evaluate(BytesFilteredBin, Socket, FilteredState),
    %%{NewCommandBufferBin, NewState} = navigate_in_buffer(BytesFilteredBin, CommandBufferBin, FilteredState, Socket),

    Msg = case navigate_in_buffer(BytesFilteredBin, CommandBufferBin, FilteredState, Socket) of
	      {exit, NewCommandBufferBin, NewState}  -> 
		  ts_connection_print_process:stop(PrintProcessPID), % stop the print process
		  {stop, normal, NewState#state{command_buffer_bin = NewCommandBufferBin}};
	      {NewCommandBufferBin, NewState} -> 
		  {noreply, NewState#state{command_buffer_bin = NewCommandBufferBin}}
	  end,
    Msg;
handle_info({tcp_closed, Socket}, #state{socket=Socket}=State) ->
    gen_tcp:close(Socket),
    error_logger:info_msg("Socket closed: (~w)~n", [Socket]),
    {stop, normal, State};
handle_info({tcp_error, Socket, Reason}, #state{socket=Socket}=State) ->
    error_logger:info_msg("Socket error:(~w)~n", [Reason]),    
    gen_tcp:close(Socket),
    {stop, normal, State};
handle_info(_Info, State) ->
    error_logger:info_msg("tcp_connection (~w) received unhandled Info message (~w) ~n", [self(), _Info]),
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
filter_negotiation_messages(<<>>, Acc, State) when is_binary(Acc)->
    {Acc, State};
filter_negotiation_messages(BytesBin, Acc, State) when is_binary(BytesBin),is_binary(Acc)->
    case BytesBin of
	<<?IAC:8, ?SB:8, ?WINDOW_SIZE:8, WIDTH:16, ?IAC:8, HEIGHT:16, ?IAC:8, ?IAC:8, ?SE:8, Remain/binary>>
	  when HEIGHT==255, WIDTH ==255->
	    %% for now hight or width <> 255 is allowed
	    error_logger:info_msg("Negotiate About Window Size: width ~p, height ~p ~n",[WIDTH,HEIGHT]),	
	    filter_negotiation_messages(Remain, Acc, State#state{window_width=WIDTH, window_height=HEIGHT});

	<<?IAC:8, ?SB:8, ?WINDOW_SIZE:8, WIDTH:16, HEIGHT:16, ?IAC:8, ?IAC:8, ?SE:8, Remain/binary>> when HEIGHT==255->
	    %% for hight = 255
	    error_logger:info_msg("Negotiate About Window Size: width ~p, height ~p ~n",[WIDTH,HEIGHT]),	
	    filter_negotiation_messages(Remain, Acc, State#state{window_width=WIDTH, window_height=HEIGHT});

	<<?IAC:8, ?SB:8, ?WINDOW_SIZE:8, WIDTH:16, ?IAC:8, HEIGHT:16, ?IAC:8, ?SE:8, Remain/binary>> when WIDTH ==255->
	    %% for width = 255
	    error_logger:info_msg("Negotiate About Window Size: width ~p, height ~p ~n",[WIDTH,HEIGHT]),	
	    filter_negotiation_messages(Remain, Acc, State#state{window_width=WIDTH, window_height=HEIGHT});

	<<?IAC:8, ?SB:8, ?WINDOW_SIZE:8, WIDTH:16, HEIGHT:16, ?IAC:8, ?SE:8, Remain/binary>> ->
	    %% for now hight or width <> 255 is allowed
	    error_logger:info_msg("Negotiate About Window Size: width ~p, height ~p ~n",[WIDTH,HEIGHT]),	
	    filter_negotiation_messages(Remain, Acc, State#state{window_width=WIDTH, window_height=HEIGHT});

	<<?IAC:8, ?DONT:8, Third:8, Remain/binary>> ->
	    error_logger:info_msg("DONT : ~p~n",[option(Third)]),
	    filter_negotiation_messages(Remain, Acc, State);

	<<?IAC:8, ?DO:8, Third:8, Remain/binary>> ->
	    error_logger:info_msg("DO : ~p~n",[option(Third)]),
	    filter_negotiation_messages(Remain, Acc, State);

	<<?IAC:8, ?WONT:8, Third:8, Remain/binary>> ->
	    error_logger:info_msg("WONT : ~p~n",[option(Third)]),
	    filter_negotiation_messages(Remain, Acc, State);

	<<?IAC:8, ?WILL:8, Third:8, Remain/binary>> ->
	    error_logger:info_msg("WILL : ~p~n",[option(Third)]),	
	    filter_negotiation_messages(Remain, Acc, State);

	<<NewChar:8, Remain/binary>> ->
	    filter_negotiation_messages(Remain, <<Acc/binary,NewChar>>, State)
    end.

option(?TRANSMIT_BINARY) -> 'TRANSMIT-BINARY';
option(?ECHO) -> 'ECHO';
option(?SUPPRESS_GO_AHEAD) -> 'SUPPRESS-GO-AHEAD';
option(N) when is_integer(N) -> N.

%% evaluate(<<>>, _Socket, State) ->
%%     State;
%% evaluate(<<"ö", Remain/binary>>, Socket, State)->    
%%     gen_tcp:send(Socket, <<"Hura!!! Found ö!!!">>),
%%     evaluate(<<Remain/binary>>, Socket, State);
%% evaluate(<<"x", Remain/binary>>, Socket, State)->    
%%     gen_tcp:send(Socket, <<"terminating">>),
%%     evaluate(<<Remain/binary>>, Socket, State#state{stop=true});
%% evaluate(<<Anything:8, Remain/binary>>, Socket, State) ->
%%     gen_tcp:send(Socket, <<Anything>>),
%%     evaluate(<<Remain/binary>>, Socket, State).



navigate_in_buffer(<<>>, Acc, State, Socket) when is_binary(Acc), is_record(State, state), is_port(Socket)->
    {Acc, State};

navigate_in_buffer(BytesBin, Acc, State, Socket) when is_binary(BytesBin), is_binary(Acc), is_record(State, state),is_port(Socket)->
    case BytesBin of 
	%% Backspace-key
	<<127, Remain/binary>> when State#state.position > 0->
	    gen_tcp:send(Socket, <<?BS>>),
	    SecondPartLen = byte_size(Acc)- State#state.position,
	    SecondPart = binary:part(Acc, State#state.position, SecondPartLen),
	    io:format("~p, ~p, ~p ~n",[SecondPart, State#state.position,SecondPartLen]),
	    gen_tcp:send(Socket,<<SecondPart/binary," ">>),
	    gen_tcp:send(Socket,n_times((SecondPartLen+1), <<?BS>>)),
	    NewAcc = <<(binary:part(Acc, 0, State#state.position-1))/binary, (binary:part(Acc, State#state.position, byte_size(Acc)- State#state.position))/binary>>,
	    navigate_in_buffer(Remain, NewAcc, State#state{position = State#state.position-1}, Socket);
	<<127, Remain/binary>> when State#state.position == 0->
	    gen_tcp:send(Socket,<<?BEL>>),
	    navigate_in_buffer(Remain, Acc, State, Socket);
	%% DEL-key
	<<"\e[3~", Remain/binary>>  when  byte_size(Acc) > State#state.position->
	    SecondPartLen = byte_size(Acc)- (State#state.position+1),
	    SecondPart = binary:part(Acc, State#state.position+1, SecondPartLen),
	    io:format("~p, ~p, ~p ~n",[SecondPart, State#state.position+1, SecondPartLen]),
	    gen_tcp:send(Socket,<<SecondPart/binary," ">>),
	    gen_tcp:send(Socket,n_times((SecondPartLen+1), <<?BS>>)),
	    NewAcc = <<(binary:part(Acc, 0, State#state.position))/binary, (binary:part(Acc, State#state.position+1, byte_size(Acc)- (State#state.position+1)))/binary>>,
	    navigate_in_buffer(Remain, NewAcc, State, Socket);
	%% DEL-key
	<<"\e[3~", Remain/binary>>  when  byte_size(Acc) == State#state.position->
	    gen_tcp:send(Socket,<<?BEL>>),
	    navigate_in_buffer(Remain, Acc, State, Socket);
	%% left-key
	<<"\e[D", Remain/binary>>  when State#state.position > 0->
	    gen_tcp:send(Socket,<<"\e[D">>),
	    %% delete all whitespaces right to the curser position
	    NewAcc = <<(binary:part(Acc, 0, State#state.position-1))/binary, 
		       (binary:list_to_bin(string:strip(binary:bin_to_list(binary:part(Acc, State#state.position-1, byte_size(Acc)- (State#state.position-1))),right)))/binary>>,
	    navigate_in_buffer(Remain, NewAcc, State#state{position = State#state.position-1}, Socket);
	%% left-key
	<<"\e[D", Remain/binary>>  when State#state.position == 0->
	    gen_tcp:send(Socket,<<?BEL>>),
	    navigate_in_buffer(Remain, Acc, State, Socket);
	%% right-key
	<<"\e[C", Remain/binary>> when  byte_size(Acc) > State#state.position->
	    gen_tcp:send(Socket,<<"\e[C">>),
	    navigate_in_buffer(Remain, Acc, State#state{position = State#state.position+1}, Socket);
	%% right-key
	<<"\e[C", Remain/binary>> when  byte_size(Acc) == State#state.position->
	    gen_tcp:send(Socket,<<?BEL>>),
	    navigate_in_buffer(Remain, Acc, State, Socket);
	%% Pos1-Key
	<<"\eOH", Remain/binary>>->
	    gen_tcp:send(Socket,n_times((State#state.position), <<?BS>>)),
	    navigate_in_buffer(Remain, Acc, State#state{position=0}, Socket);
	%% End-key
	<<"\eOF", Remain/binary>> ->
	    SecondPartLen = byte_size(Acc)- State#state.position,
	    SecondPart = binary:part(Acc, State#state.position, SecondPartLen),
	    io:format("~p, ~p, ~p ~n",[SecondPart, State#state.position,SecondPartLen]),
 	    gen_tcp:send(Socket,<<SecondPart/binary>>),
	    navigate_in_buffer(Remain, Acc, State#state{position=byte_size(Acc)}, Socket);

	%% Tab-key: Command completion, when position is last character of line
	<<"\t", Remain/binary>> when byte_size(Acc) == State#state.position ->
	    io:format("Commandline buffer: '~p'~n",[Acc]),
	    Partially_fun = fun(X)->case X of {partially, _State} -> true;_-> false end end,
	    Matchlist = ts_telnet_registration:test_commandstring(State#state.node, binary:bin_to_list(Acc), Partially_fun, provide_hidden),
	    io:format("Matchlist : ~p~n", [Matchlist]),
	    Set_of_Completions = ts_telnet_registration:get_completion_list(Matchlist),
	    io:format("Set_of_Completions : ~p~n", [Set_of_Completions]),
	    case length(Set_of_Completions) of
		%% no completions
		0 -> gen_tcp:send(Socket,<<?BEL>>), 
		     navigate_in_buffer(Remain, Acc, State#state{position = byte_size(Acc)}, Socket);
		%% exactly one completion
		1 -> [TabCompletion] = ordsets:to_list(Set_of_Completions),
		     TabCompletionBin = binary:list_to_bin(TabCompletion),
		     io:format("Tab-Completion ~p~n",[TabCompletionBin]),
		     TabCompletionBinLen = byte_size(TabCompletionBin),
		     io:format("~p, ~p, ~p ~n",[TabCompletionBin, State#state.position, TabCompletionBinLen]),
		     gen_tcp:send(Socket,<<TabCompletionBin/binary>>),
		     NewAcc = <<Acc/binary, TabCompletionBin/binary>>,
		     navigate_in_buffer(Remain, NewAcc, State#state{position = byte_size(NewAcc)}, Socket);
		%% multiple completions.
		_ -> Set_of_Options = ts_telnet_registration:get_option_list(Matchlist),
		     io:format("Options: ~p~n",[Set_of_Options]),
		     gen_tcp:send(Socket,<<?CR>>),
		     gen_tcp:send(Socket,<<?LF>>), 
		     print_options(ordsets:to_list(Set_of_Options), State#state.window_width, Socket),
		     gen_tcp:send(Socket,<<?CR>>),
		     gen_tcp:send(Socket,<<?LF>>),
		     gen_tcp:send(Socket,get_prompt(State)),
						%SecondPartLen = byte_size(Acc)- State#state.position,
		     gen_tcp:send(Socket,<<Acc/binary>>),
						%gen_tcp:send(Socket,n_times((SecondPartLen), <<?BS>>)),
		     navigate_in_buffer(Remain, Acc, State#state{position = byte_size(Acc)}, Socket)
	    end;


	%% Tab-key: Ignore tab, when position is not last character of line
	<<"\t", Remain/binary>> ->
	    gen_tcp:send(Socket,<<?BEL>>),
	    navigate_in_buffer(Remain, Acc, State, Socket);

	%% Return-key: Execute the command
	<<?CR, Remain/binary>> ->
	    io:format("Commandline buffer: '~p'~n",[Acc]),
	    MappedCommandAbbreviated = ts_abbreviation_parser:test_commandstring_abbreviated(State#state.node, string:strip(binary:bin_to_list(Acc))),
	    MatchTrue_fun = fun(X)->case X of {true, _, _, _ , _ } -> true;_-> false end end,
	    MatchlistCommandAbbreviated = lists:filter(MatchTrue_fun, MappedCommandAbbreviated),
	    Ok_fun = fun(X)->case X of {ok, _State} -> true;_-> false end end,
	    Matchlist = ts_telnet_registration:test_commandstring(State#state.node, string:strip(binary:bin_to_list(Acc), right), Ok_fun, provide_hidden),
	    io:format("Matchlist : ~p~n", [Matchlist]),
	    Set_of_Matching_Commands = ts_telnet_registration:get_command_execution_list(Matchlist),
	    io:format("Set_of_Matching_Commands : ~p~n", [Set_of_Matching_Commands]),
	    case length(MatchlistCommandAbbreviated) of
		%% no matching commands, thus look at the failed commands and determine the longest failed command to put the indicator '^'
		0 ->  Partially_fun = fun(X)->case X of {partially, _State} -> true;_-> false end end,
		      PartiallyMatchlist = ts_telnet_registration:test_commandstring(State#state.node, binary:bin_to_list(Acc), Partially_fun,provide_hidden),
		      io:format("PartiallyMatchlist : ~p~n", [PartiallyMatchlist]),
		      case length(PartiallyMatchlist) of
			  0 -> Fail_fun = fun(X)->case X of {fail, _State} -> true;_-> false end end,
			       FailMatchlist = ts_telnet_registration:test_commandstring(State#state.node, binary:bin_to_list(Acc), Fail_fun, provide_hidden),
			       io:format("FailMatchlist : ~p~n", [FailMatchlist]),
			       FailMatchlist_mapped = lists:map(fun(H)-> {fail,#pstate{parsed_list=A}}=H,io:format("A: ~p~n", [A]), A end, FailMatchlist), 
			       io:format("FailMatchlist mappped: ~p~n", [FailMatchlist_mapped]),
			       ErrorPosition=lists:max(lists:map(fun(H)-> string:len(string:join (H, "")) end, FailMatchlist_mapped)), 
			       gen_tcp:send(Socket,<<?BEL>>), 
			       gen_tcp:send(Socket,<<?CR>>),
			       gen_tcp:send(Socket,<<?LF>>),
		 	       gen_tcp:send(Socket,get_prompt(State)),
			       gen_tcp:send(Socket,n_times((ErrorPosition), <<" ">>)), 
			       gen_tcp:send(Socket,<<"^">>),
			       gen_tcp:send(Socket,<<?CR>>),
			       gen_tcp:send(Socket,<<?LF>>),
			       gen_tcp:send(Socket,<<"% Invald input detected at '^' marker">>),
			       gen_tcp:send(Socket,<<?CR>>),
			       gen_tcp:send(Socket,<<?LF>>),
			       gen_tcp:send(Socket,get_prompt(State)),
			       gen_tcp:send(Socket,<<Acc/binary>>), 
			       navigate_in_buffer(Remain, Acc, State#state{position = byte_size(Acc), 
									   history_index = 0,
									   history_buffer = queue_element(binary:list_to_bin(string:strip(binary:bin_to_list(Acc))), State#state.history_buffer, State#state.history_depth)}, Socket);

			  _ -> gen_tcp:send(Socket,<<?CR>>),
			       gen_tcp:send(Socket,<<?LF>>),
			       gen_tcp:send(Socket,<<"% Incomplete command, complete with:">>),
			       Set_of_Options = ts_telnet_registration:get_option_list(PartiallyMatchlist),
			       io:format("Options: ~p~n",[Set_of_Options]),
			       gen_tcp:send(Socket,<<?CR>>),
			       gen_tcp:send(Socket,<<?LF>>), 
			       print_options(ordsets:to_list(Set_of_Options), State#state.window_width, Socket),
			       gen_tcp:send(Socket,<<?CR>>),
			       gen_tcp:send(Socket,<<?LF>>),
			       gen_tcp:send(Socket,get_prompt(State)),
			       gen_tcp:send(Socket,<<Acc/binary>>), 
			       navigate_in_buffer(Remain, Acc, State#state{position = byte_size(Acc), 
									   history_index = 0, 
									   history_buffer = queue_element(binary:list_to_bin(string:strip(binary:bin_to_list(Acc))), State#state.history_buffer, State#state.history_depth) }, Socket)
		      end;
		%% exactly one matching command, thus execute the command with the parameters
		1 -> [{true, NumberList, SelectionList, StrList, Command}] = MatchlistCommandAbbreviated,
		     CommandParam = #command_param{selection_list = SelectionList, number_list = NumberList, str_list = StrList, index_list = State#state.index},
		     gen_tcp:send(Socket,<<?CR>>),
		     gen_tcp:send(Socket,<<?LF>>),
		     case resolve_optional_alias(Command) of 
			 {warning, Warning} ->
			     gen_tcp:send(Socket,list_to_binary(Warning)),
			     gen_tcp:send(Socket,<<?CR, ?LF, ?CR, ?LF>>),
			     NewAcc = <<"">>,
			     %% put entered command into histroy buffer
			     NewState =State#state{
					 history_buffer = queue_element(binary:list_to_bin(string:strip(binary:bin_to_list(Acc))), State#state.history_buffer, State#state.history_depth), 
					 history_index = 0,
					 position = 0},	
			     gen_tcp:send(Socket,get_prompt(NewState)),
			     gen_tcp:send(Socket,<<NewAcc/binary>>), 
			     navigate_in_buffer(Remain, NewAcc, NewState, Socket);
			 {command, ResolvedAliasCommand} ->
			     {Result, NewState} = execute_command(ResolvedAliasCommand, CommandParam, State, Socket),  
			     Res = handle_execution_result(Socket, NewState, Result, Acc),
			     case Res of
				{exit, NewState1} ->
				     {exit, NewState1};
				 {continue, NewAcc1, NewState1} ->
				     navigate_in_buffer(Remain, NewAcc1, NewState1, Socket)
			     end
		     end;

		%% multiple matching commands, this is an error to register more than one command matching at the same time. 
		%% Thus list the errorous commands.
		_ -> io:format("Ambigous commands: ~p~n",[Acc]),
		     gen_tcp:send(Socket,<<?CR>>),
		     gen_tcp:send(Socket,<<?LF>>),
		     gen_tcp:send(Socket,<<"% Ambigous command!!">>),
		     gen_tcp:send(Socket,<<?CR>>),
		     gen_tcp:send(Socket,<<?LF>>),
		     gen_tcp:send(Socket,get_prompt(State)),
		     SecondPartLen = byte_size(Acc)- State#state.position,
		     gen_tcp:send(Socket,<<Acc/binary>>),
		     gen_tcp:send(Socket,n_times((SecondPartLen), <<?BS>>)),
		     navigate_in_buffer(Remain, Acc, State#state{position = byte_size(Acc), history_index = 0}, Socket)
	    end;

	%% Insert-key 
	<<"\e[2~", Remain/binary>> when State#state.insertion_mode == insert ->
	    navigate_in_buffer(Remain, Acc, State#state{insertion_mode = delete}, Socket);

	%% Insert-key
	<<"\e[2~", Remain/binary>> when State#state.insertion_mode == delete ->
	    navigate_in_buffer(Remain, Acc, State#state{insertion_mode = insert}, Socket);

	%% Page-Up-key ignore
	<<"\e[5~", Remain/binary>> ->
	    navigate_in_buffer(Remain, Acc, State#state{position = byte_size(Acc)}, Socket);

	%% Page-Down-key ignore
	<<"\e[6~", Remain/binary>> ->
	    navigate_in_buffer(Remain, Acc, State#state{position = byte_size(Acc)}, Socket);

	%% Up-key ignore
	<<"\e[A", Remain/binary>> ->
	    gen_tcp:send(Socket,n_times(State#state.position, <<?BS>>)),
	    gen_tcp:send(Socket,n_times(byte_size(Acc), <<" ">>)),
	    gen_tcp:send(Socket,n_times(byte_size(Acc), <<?BS>>)),
	    case get_nth_element(State#state.history_index,State#state.history_buffer ) of 
		empty ->
		    NewAcc = <<"">>;
		{value, NewAcc} ->
		    ok
	    end,
	    gen_tcp:send(Socket,<<NewAcc/binary>>),
	    NewState = State#state{history_index = min(State#state.history_index+1, queue_len(State#state.history_buffer))},
	    navigate_in_buffer(Remain, NewAcc, NewState#state{position = byte_size(NewAcc)}, Socket);

	%% Down-key ignore
	<<"\e[B", Remain/binary>> ->
	    gen_tcp:send(Socket,n_times(State#state.position, <<?BS>>)),
	    gen_tcp:send(Socket,n_times(byte_size(Acc), <<" ">>)),
	    gen_tcp:send(Socket,n_times(byte_size(Acc), <<?BS>>)),
	    case get_nth_element(State#state.history_index,State#state.history_buffer ) of 
		empty ->
		    NewAcc = <<"">>;
		{value, NewAcc} ->
		    ok
	    end,
	    gen_tcp:send(Socket,<<NewAcc/binary>>),
	    NewState = State#state{history_index = max(State#state.history_index-1, 0)},
	    navigate_in_buffer(Remain, NewAcc, NewState#state{position = byte_size(NewAcc)}, Socket);

	%% ?-key
	<<"?", Remain/binary>> ->
	    %%io:format("SpaceBefore~n"),
	    Ok_or_partially_fun = fun(X)->case X of {ok, _State} -> true;{partially, _State} -> true;_-> false end end,
	    Matchlist = ts_telnet_registration:test_commandstring(State#state.node, string:strip(binary:bin_to_list(Acc)), Ok_or_partially_fun, filter_hidden),
	    io:format("Matchlist : ~p~n", [Matchlist]),
	    Set_of_Commands = ts_telnet_registration:get_command_list(Matchlist),
	    io:format("Set_of_Commands : ~p~n", [Set_of_Commands]),
	    MatchedElements = length(string:tokens(string:strip(binary:bin_to_list(Acc)), " ")),
	    gen_tcp:send(Socket,<<?CR>>),
	    gen_tcp:send(Socket,<<?LF>>), 
	    %% check for space before curser position
	    ElementOffset = case (State#state.position > 0) of % and (binary_part(Acc, (State#state.position-1),1) == <<" ">>) of
				true  -> 
				    case (binary_part(Acc, (State#state.position-1),1) ==  <<" ">>) of
					true -> 1;
					false -> 0
				    end;
				false -> 0
			    end,
	    Command_help_List = generate_command_help_list(Set_of_Commands, max(MatchedElements+ElementOffset,1)),
	    io:format("Command_help_List: ~p~n",[Command_help_List]),
	    print_command_help_list(Command_help_List, Socket),
	    gen_tcp:send(Socket,<<?CR>>),
	    gen_tcp:send(Socket,<<?LF>>),
	    gen_tcp:send(Socket,get_prompt(State)),
	    SecondPartLen = byte_size(Acc)- State#state.position,
	    gen_tcp:send(Socket,<<Acc/binary>>),
	    gen_tcp:send(Socket,n_times((SecondPartLen), <<?BS>>)),
	    navigate_in_buffer(Remain, Acc, State , Socket);

	%% Ignore characters with Bit 7 set or smaller than 32 
	%% (hope thats the right approach to filter-out multi-byte characters)  

	<<26, Remain/binary>> -> % control-z is same as 'exit' command.
	    case queue:is_empty(State#state.configuration_path) of
		true ->
		    exit; % Exit the program
		false ->
		    %% get the last node from the queue
		    {{value,Node}, ConfigurationPath} = queue:out_r(State#state.configuration_path),
		    NewState = State#state{
				 configuration_path = ConfigurationPath,
				 node = Node, 
				 history_index = 0,
				 position = 0},
		    receive_output(Socket), % receive characters for 100 ms
		    gen_tcp:send(Socket,<<?CR>>),
		    gen_tcp:send(Socket,<<?LF>>),
		    NewAcc = <<"">>,	
		    gen_tcp:send(Socket,get_prompt(NewState)),
		    gen_tcp:send(Socket,<<NewAcc/binary>>), 
		    navigate_in_buffer(Remain, NewAcc, NewState, Socket)
	    end;

	<<0, Remain/binary>> -> % Ignore ASCII character 0x00, no bell
	    navigate_in_buffer(Remain, Acc, State, Socket);

	<<NewChar, Remain/binary>> when  NewChar < 32;  NewChar >= 128 ->
	    io:format("ErrorusNewChar:~p~n ",[NewChar]),
	    gen_tcp:send(Socket,<<?BEL>>),
	    navigate_in_buffer(Remain, Acc, State, Socket);

	<<NewChar, Remain/binary>> when  byte_size(Acc) == State#state.position->
	    gen_tcp:send(Socket,<<NewChar>>),
	    SecondPart = <<"">>,
	    io:format("Second part: ~p~n",[SecondPart]),
	    NewAcc = <<(binary:part(Acc, 0, State#state.position))/binary, NewChar, SecondPart/binary>>,
	    navigate_in_buffer(Remain, NewAcc, State#state{position= State#state.position+1}, Socket);

	%% overwrite mode
	<<NewChar, Remain/binary>> when  byte_size(Acc) > State#state.position, State#state.insertion_mode == delete ->
	    gen_tcp:send(Socket,<<NewChar>>),
	    SecondPart = binary:part(Acc, State#state.position+1, byte_size(Acc)- (State#state.position+1)),
	    io:format("Second part: ~p~n",[SecondPart]),
	    NewAcc = <<(binary:part(Acc, 0, State#state.position))/binary, NewChar, SecondPart/binary>>,
	    navigate_in_buffer(Remain, NewAcc, State#state{position=State#state.position+1}, Socket);

	%% insert mode
	<<NewChar, Remain/binary>> when  byte_size(Acc) > State#state.position, State#state.insertion_mode == insert->
	    gen_tcp:send(Socket,<<NewChar>>),
	    SecondPartLen = byte_size(Acc)- (State#state.position),
	    SecondPart = binary:part(Acc, State#state.position, SecondPartLen),
	    io:format("~p, ~p, ~p ~n",[SecondPart, State#state.position+1, SecondPartLen]),
	    io:format("Second part: ~p~n",[SecondPart]),
	    gen_tcp:send(Socket,<<SecondPart/binary," ">>),
	    gen_tcp:send(Socket,n_times((SecondPartLen+1), <<?BS>>)),
	    NewAcc = <<(binary:part(Acc, 0, State#state.position))/binary, NewChar, SecondPart/binary>>,
	    navigate_in_buffer(Remain, NewAcc, State#state{position=State#state.position+1}, Socket)
    end.

n_times(N, Value)  when N >= 0, is_binary(Value) ->
    n_times(N, Value, <<>>).

n_times(0, Value, Acc) when is_binary(Value), is_binary(Acc)->
    Acc;

n_times(N, Value, Acc) when N >= 0,is_binary(Value), is_binary(Acc)->
    n_times(N-1, Value, <<Acc/binary,Value/binary>>).


print_options(Option_List, WindowWidth, Socket) -> 
    print_options(Option_List, [], 0, WindowWidth, Socket).

print_options([], _Acc, _Pos, _WindowWidth, _Socket) -> 
    true;

print_options([Head|Tail], Acc, Pos, WindowWidth, Socket) ->
    Offset = 20,
    if 
	(Pos + Offset) > WindowWidth -> 
	    NewPos = Offset,
	    gen_tcp:send(Socket,<<?CR>>),
	    gen_tcp:send(Socket,<<?LF>>),
	    gen_tcp:send(Socket,string:left(Head, max(Offset,length(Head)+1)));
	true ->
	    NewPos = Pos + Offset,
	    gen_tcp:send(Socket,string:left(Head, max(Offset,length(Head)+1)))    
    end,
    print_options(Tail, Acc, NewPos, WindowWidth, Socket).


get_prompt(State)->
    get_name_prompt()++
	get_configuration_level_prompt(State)++
	get_exec_mode_prompt(State).

get_name_prompt()->
    ets:lookup_element(server_data_table,hostname, 2).

get_configuration_level_prompt(State)->
    case ets:lookup(commandTable, State#state.node) of
	[Node] -> 
	    case Node#node.configuration_level of
		undefined ->
		    "";
		Config_Level -> 
		    "("++Config_Level++")"
	    end
    end.

get_exec_mode_prompt(State)->
    case ets:lookup(commandTable, State#state.node) of
	[Node] -> 
	    case Node#node.exec_mode of
		user ->
		    "> ";
		privileged -> 
		    "# "
	    end
    end.

%%% command history queue

queue_new() ->
    queue:new().

queue_len(Queue) ->
    queue:len(Queue).

queue_element(Element, Queue, MaxLength) ->
    QueueLength = queue:len(Queue), 
    if  
	QueueLength < MaxLength -> 
	    QueueNew = queue:in(Element,Queue);
	true -> 
	    QueueNew1 = queue:in(Element,Queue),
	    {_QueueDump, QueueNew} = queue:split(1, QueueNew1),
	    io:format("QueueNew1: ~p, QueueDump: ~p ~n", [QueueNew1, _QueueDump])
    end,
    QueueNew.

get_nth_element(N, Queue) ->
    io:format("Get_nth_element, N:~p Queue: ~p~n",[N,Queue]),
    {FirstPart,_SecondPart} = queue:split(queue:len(Queue)-N,Queue),
    io:format("First Part: ~p~n", [FirstPart]),
    case queue:out_r(FirstPart) of
	{{value, Nth_element}, _Queue} -> 
	    io:format("value:~p ~n",[Nth_element]),
	    {value, Nth_element};
	{empty, _Queue} ->
	    io:format("empty:~n",[]),
	    empty
    end.

resolve_optional_alias(Command)->
    case Command#command.alias_ref of
	undefined -> % alias is not used 
	    {command, Command};

	_Other -> % alias is used, find alias_ref
	    case find_alias_def(Command#command.alias_ref) of
		{alias_found,AliasRefCommand} -> % alias_ref was found
		    {command, AliasRefCommand};
		alias_not_found ->
		    {warning, "Warning: alias_def not found!!!"}
	    end
    end.

execute_command(Command, CommandParam, State, Socket)->
    SelectionList = CommandParam#command_param.selection_list, 
    NumberList = CommandParam#command_param.number_list, 
    StrList = CommandParam#command_param.str_list, 
    Index = State#state.index,
    io:format("Command: ~p SelectionList: ~p NumberList: ~p StrList: ~p IndexList: ~p~n",[Command, CommandParam#command_param.selection_list, CommandParam#command_param.number_list, CommandParam#command_param.str_list, State#state.index]),
    Command_fun = Command#command.funcname,
    %% Execute the fun 
    %%Result = case Command_fun({vty, State#state.print_process_PID}, #command_param{selection_list = SelectionList, number_list = NumberList, str_list = StrList, index_list = State#state.index}) of
    Result = case Command_fun({vty_socket, State#state.socket}, #command_param{selection_list = SelectionList, number_list = NumberList, str_list = StrList, index_list = State#state.index}) of
		 cmd_warning ->
		     gen_tcp:send(Socket,<<?BEL>>),
		     NewState1 = State,
		     cmd_warning;
		 cmd_enable ->
		     NewState1 = State#state{node = enable_node},
		     cmd_success;	 
		 cmd_disable ->
		     NewState1 = State#state{node = view_node},
		     cmd_success;
		 cmd_end ->
		     NewState1 = State#state{
				    configuration_path = queue:new(),
				    node = enable_node, 
				    index = []},
		     cmd_success;
		 cmd_exit ->
		     case queue:is_empty(State#state.configuration_path) of
			 true ->
			     NewState1 = State,
			     cmd_exit; % Exit the program
			 false ->
			     %% get the last node from the queue
			     {{value,{Node, Index}}, ConfigurationPath} = queue:out_r(State#state.configuration_path),
			     NewState1 = State#state{
					    configuration_path = ConfigurationPath,
					    node = Node,
					    index = Index},
			     io:format("Index: ~p~n",[Index]),
			     cmd_success
		     end;
		 {cmd_enter_node, NewNode} ->
		     %% put current node in the configuration path queue
		     NewState1 = State#state{
				    configuration_path = queue:in({State#state.node, State#state.index}, State#state.configuration_path),
				    node = NewNode,
				    index = State#state.index},
		     io:format("Index: ~p~n",[State#state.index]),
		     cmd_success;
		 {cmd_enter_node, NewNode, NewIndex} ->
		     %% put current node in the configuration path queue
		     NewState1 = State#state{
				    configuration_path = queue:in({State#state.node, State#state.index}, State#state.configuration_path),
				    node = NewNode,
				    index = [NewIndex|State#state.index]},
		     io:format("Index: ~p~n",[NewState1#state.index]),
		     cmd_success;
		 cmd_list ->
		     %% list all commands on the screen
		     CommandList = get_non_hidden_command_list(State#state.node),
		     Fun = fun(A,B) -> A < B end,
		     SortedCommandList = lists:sort(Fun, CommandList),
		     print_list_to_telnet_console(Socket, SortedCommandList),
						%print_command_list(Socket, State#state.node),
		     NewState1 = State,
		     cmd_success;
		 cmd_history ->
		     %% display commandline history on the screen
		     CommandHistoryList = generate_commandline_history_list(State#state.history_buffer),
		     print_list_to_telnet_console(Socket, CommandHistoryList),
						%print_commandline_history(Socket, State#state.history_buffer),
		     NewState1 = State,
		     cmd_success;
		 cmd_success ->
		     NewState1 = State,
		     cmd_success;
		 _ ->
		     NewState1 = State,
		     cmd_unknown

	     end,
    {Result, NewState1}.


handle_execution_result(Socket, State, Result, Acc) ->
    %% make sure the output from the fun comes before the prompt below.
    timer:sleep(10), 
    case Result of
	cmd_exit ->
	    {exit, Acc, State}; 
	cmd_success ->
	    gen_tcp:send(Socket,<<?CR>>),
	    gen_tcp:send(Socket,<<?LF>>),
	    NewAcc = <<"">>,
	    %% put entered command into histroy buffer
	    NewState =State#state{
			history_buffer = queue_element(binary:list_to_bin(string:strip(binary:bin_to_list(Acc))), State#state.history_buffer, State#state.history_depth), 
			history_index = 0,
			position = 0},	
	    gen_tcp:send(Socket,get_prompt(NewState)),
	    gen_tcp:send(Socket,<<NewAcc/binary>>), 
	    {continue, NewAcc, NewState};

	cmd_warning ->
	    gen_tcp:send(Socket,<<?CR>>),
	    gen_tcp:send(Socket,<<?LF>>),
	    NewAcc = <<"">>,
	    %% put entered command into histroy buffer
	    NewState =State#state{
			history_buffer = queue_element(binary:list_to_bin(string:strip(binary:bin_to_list(Acc))), State#state.history_buffer, State#state.history_depth), 
			history_index = 0,
			position = 0},
	    gen_tcp:send(Socket,<<"Warning error!!!", ?CR, ?LF>>),
	    gen_tcp:send(Socket,<<"Be arware of what you are doing !!!", ?BEL, ?CR, ?LF>>),	
	    gen_tcp:send(Socket, get_prompt(NewState)),
	    gen_tcp:send(Socket,<<NewAcc/binary>>),
	    {continue, NewAcc, NewState};
	_ ->
	    gen_tcp:send(Socket,<<?CR>>),
	    gen_tcp:send(Socket,<<?LF>>),
	    NewAcc = <<"">>,
	    %% put entered command into histroy buffer
	    NewState = State#state{
			 history_buffer = queue_element(binary:list_to_bin(string:strip(binary:bin_to_list(Acc))), State#state.history_buffer, State#state.history_depth), 
			 history_index = 0,
			 position = 0},
	    gen_tcp:send(Socket,<<"Implementation error!!!", ?CR, ?LF>>),
	    gen_tcp:send(Socket,<<"Invald command exit command. This should not occurr !!!", ?BEL, ?CR, ?LF>>),	
	    gen_tcp:send(Socket,get_prompt(NewState)),
	    gen_tcp:send(Socket,<<NewAcc/binary>>), 
	    {continue, NewAcc, NewState}
    end.

generate_command_help_list(Command_List, MatchedElements) -> 
    generate_command_help_list(Command_List, [], MatchedElements).

generate_command_help_list([], Acc, _MatchedElements) ->  
    %% remove duplicates 
    ordsets:to_list(ordsets:from_list(Acc));

generate_command_help_list([Head|Tail], Acc,  MatchedElements) ->
    %% match the nth command-string with the nth help-sting%
    %% add info for pressing-carrige return
    generate_command_help_list(Tail, [{lists:nth(MatchedElements, Head#command.cmdstr ++ ["<cr>"]), lists:nth(MatchedElements, Head#command.helpstr ++ [""])}|Acc], MatchedElements).

print_command_help_list([], _Socket) ->
    true;

print_command_help_list([Head|Tail], Socket) ->
    {CmdElementStr,HelpElementStr} = Head,  
    gen_tcp:send(Socket, CmdElementStr),
    gen_tcp:send(Socket," "),
    gen_tcp:send(Socket,n_times(max((20-length(CmdElementStr)),0), <<" ">>)),
    gen_tcp:send(Socket, HelpElementStr),  
    gen_tcp:send(Socket,<<?CR>>),
    gen_tcp:send(Socket,<<?LF>>),	 
    print_command_help_list(Tail, Socket).


find_alias_def(Command_alias_def) ->
    FirstNodeKey = ets:first(commandTable),
    find_alias_def(Command_alias_def, FirstNodeKey).

find_alias_def(Command_alias_def, NodeKey)->
    case NodeKey of 
	'$end_of_table' -> % last registered node already searched
	    alias_not_found;
	_ ->
	    [Node] = ets:lookup(commandTable, NodeKey),
	    io:format("Node: ~w~n",[Node]),
	    CommandListTableID = Node#node.commandListTableID,
	    CommandListTable = ets:tab2list(CommandListTableID),
	    %% io:format("CommandListTable: ~p~n",[CommandListTable]),
	    case find_alias_def_in_elements(Command_alias_def, CommandListTable) of
		alias_not_found ->
		    NextNodeKey = ets:next(commandTable,NodeKey),
		    find_alias_def(Command_alias_def, NextNodeKey);
		{alias_found, Command} ->
		    {alias_found, Command}
	    end
    end.

find_alias_def_in_elements(_Command_alias_def, [])->
    alias_not_found;

find_alias_def_in_elements(Command_alias_def, [Head|Tail])->
    {_NodeID, Command} = Head,
    case Command#command.alias_def of
	undefined -> % ignore this element, as no alias_def defined for this node
	    io:format("Element ignored, as alias_def not defined: ~p~n",[Command#command.cmdstr]),
	    find_alias_def_in_elements(Command_alias_def, Tail);
	Command_alias_def -> % alias found
	    io:format("Alias element found: ~p~n",[Command#command.cmdstr]),
	    {alias_found, Command};
	_ -> % ignore this element, as no alias_def defined for this node
	    io:format("Element ignored, as different alias_def : ~p~n",[Command#command.cmdstr]),
	    find_alias_def_in_elements(Command_alias_def, Tail)
    end.


get_non_hidden_command_list(NodeID)->
    %% lookup ets table identifier of given node in commandTable
    [#node{nodeID = NodeID, commandListTableID = NodeTableID}] = ets:lookup(commandTable, NodeID),
    %% convert table of current node to list
    CommandList = ts_telnet_registration:create_command_list(ets:tab2list(NodeTableID)),
    NonHiddenCommandList = lists:filter(fun(X) -> X#command.hidden /= yes end, CommandList),
    lists:map(fun(X) -> string:join(X#command.cmdstr, " ") end, NonHiddenCommandList).

generate_commandline_history_list(Queue) ->
    Commandline_history_list = queue:to_list(Queue),
    io:format("Commandline Queue as list: ~p~n",[Commandline_history_list]),
    Commandline_history_list.


print_list_to_telnet_console(_Socket, [])->
    true;

print_list_to_telnet_console(Socket, [Head|Tail]) ->
    gen_tcp:send(Socket, <<"  ">>), 
    gen_tcp:send(Socket, Head), 
    gen_tcp:send(Socket, <<?CR,?LF >>),
    print_list_to_telnet_console(Socket,Tail).

receive_output(Socket) ->
    receive
	{output, List} when is_list(List) ->
	    gen_tcp:send(Socket, List),
	    receive_output(Socket);
	Other ->
	    io:format("Received message, this should not occur!! ~p", [Other])
    after
	100 -> 
	    ok
    end.
