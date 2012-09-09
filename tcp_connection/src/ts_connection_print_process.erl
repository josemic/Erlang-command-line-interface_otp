%%%-------------------------------------------------------------------
%%% @author michael <michael@michael-desktop>
%%% @copyright (C) 2012, michael
%%% @doc
%%%
%%% @end
%%% Created : 20 Aug 2012 by michael <michael@michael-desktop>
%%%-------------------------------------------------------------------
-module(ts_connection_print_process).

-behaviour(gen_server).

%% API
-export([start_link/1, stop/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).

-define(SERVER, ?MODULE). 

-record(state, 
	{socket             ::port()}).

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
start_link([Socket, Instance]) -> 
    Instance_s = integer_to_list(Instance),
    Ref_s = erlang:ref_to_list(make_ref()),
    Name_s = ?MODULE_STRING ++ "_" ++ Instance_s ++ "_" ++ Ref_s,
    Name = list_to_atom (Name_s),      
    error_logger:info_report("gen_server:start_link(~p)~n",[[{local, Name},?MODULE,[Socket],[],self()]]), 
    %% Name may be left away.
    %% gen_server:start_link(?MODULE,[Socket],[]).
    gen_server:start_link({local, Name}, ?MODULE, [Socket], []).

stop(PrintProcessPID)->
    gen_server:cast(PrintProcessPID, stop). % stop the print process

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
init([Socket]) ->
    error_logger:info_msg("tcp_connection_print_process (~w) has started (~w) on Socket ~n", [self(), Socket]),
    {ok, #state{socket=Socket}}.

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
handle_cast(stop, State) ->   
    error_logger:info_msg("tcp_connection_print_process (~w) has been stopped  ~n", [self()]),
    {stop, normal, State};
handle_cast({output, List}, State)  when is_list(List) ->
    gen_tcp:send(State#state.socket, List),
    {noreply, State};
handle_cast(_Msg, State) ->    
    error_logger:info_msg("tcp_connection_print_process (~w) received unhandled message (~w) ~n", [self(), _Msg]),
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
