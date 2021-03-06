-module(tcp_connector).

-behaviour(gen_server).
-define (DEFAULT_PORT, 1025).

%% API
-export([start_link/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).

-define(SERVER, ?MODULE). 

-record(state, {port::port(),
		count::integer()}).

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
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

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
init([]) ->
    io:format("tcp_connector has started (~w)~n", [self()]),
    Port = case application:get_env(tcp_server, port) of
	       {ok, P} -> P;
	       undefined -> ?DEFAULT_PORT
	   end,
    {ok, #state{port = Port, count=0},0}. % set immediate timeout

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
handle_cast(_Msg, State) ->
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
handle_info(timeout, #state{port=Port,count=Count} = State) ->
    {ok, ListenSocket} = gen_tcp:listen(Port, [binary, {active, true}, {reuseaddr,true}]),
    error_logger:info_msg("Wait connect: ~p, ListenSocket ~p~n",[Count, ListenSocket]),
    MaxNumberOfConcurrentConnections =100000,
    {ok,NewState} = wait_for_accept_loop(ListenSocket, MaxNumberOfConcurrentConnections, 0, State),
    {noreply, NewState};
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
wait_for_accept_loop(_ListenSocket, 0, _Instance, State) ->
    {ok,State};
wait_for_accept_loop(ListenSocket, MaxNumberOfConcurrentConnections, Instance, State) ->
    {ok,Socket} = gen_tcp:accept(ListenSocket),
    Connection_Result = ts_root_sup:start_connection_worker(Socket, Instance),
    error_logger:info_msg("initiated tcp_connection_sup:start_child: Root_Sup_PID(~w), Socket(~w), Instance(~w), Result(~w)~n", [ts_root_sup, Socket, Instance, Connection_Result]),
    {ok, Connection_PID} = Connection_Result,
    gen_tcp:controlling_process(Socket, Connection_PID),		   
    NewState = State#state{count = State#state.count+1},
    wait_for_accept_loop(ListenSocket, MaxNumberOfConcurrentConnections-1, Instance+1, NewState).
