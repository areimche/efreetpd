%% Main module for ftp_connection process.
%% Handles an ftp connection to a connected client.
%% Starts a ftp_driver process, that talks to the client over a socket.
%% Also starts subprocesses for a given ftp command (e.g. uploading files, creating dirs etc.)
%% if requested by ftp_driver process. 
-module(ftp_connection).
-export([start/1, get_connection_pid/1]).
-author({"Christopher Bertels", "bakkdoor@flasht.de"}).


start(PortNr) ->
    % start loop & ftp_driver processes
    LoopPid = spawn(ftp_connection, receive_loop, []),
    register(utils:process_name(PortNr), LoopPid),
    start_driver(PortNr, LoopPid).


%% main loop, waiting for messages by the ftp_driver process.
%% if a command request comes in, we start a subprocess for the requested command.
receive_loop() ->
    % loop as long as connection is alive
    receive
	% the ftp_driver has closed the connection to the client on this port.
	{quit, PortNr} ->
	    io:format("connection closed on port: ~w~n", [PortNr]);

	% ftp_driver has told us its send_loop process, so we start our own
	{send_loop_pid, DriverSendLoop} ->
	    spawn(ftp_connection, send_loop, [DriverSendLoop]);

	% command request to be executed
	% start a subprocess to deal with the command
	{command, Command, Parameters} ->
	    execute_command(Command, Parameters),
	    receive_loop();
	
	% any other messages, we simply output and keep on going...
	Unknown ->
	    io:format("unknown command: ~w~n", [Unknown]),
	    receive_loop()
    end.


%% loop for sending requests to the client via ftp_driver process.
%% sends messages to client via DriverSendLoop (ftp_driver:send_loop) with data/commands/replies.
send_loop(DriverSendLoop) ->
    % wait for messages to forward to ftp_driver
    receive
	{reply, Reply} ->
	    case Reply of
		{data_stream, _} ->
		    io:format("sending data to client..."), % just for debugging...
		    DriverSendLoop ! Reply,
		    send_loop(DriverSendLoop);
		
		{message, Message} ->
		    io:format("sending message to client: ~p~n", [Message]),
		    DriverSendLoop ! Reply,
		    send_loop(DriverSendLoop);
		
	        UnknownReply ->
		    io:format("error: unknown reply format: ~p~n", [UnknownReply]),
		    send_loop(DriverSendLoop)
	    end;
	
	Unknown ->
	    io:format("error: unkown message in send_loop (# ~p): ~p~n", [self(), Unknown]),
	    send_loop(DriverSendLoop)
    end.


% starts a new process for a given command.
execute_command(Command, Parameters) ->
    spawn(Command, start, Parameters).


start_driver(PortNr, LoopPid) ->
    FtpDriverPid = spawn(ftp_driver, start, [PortNr, LoopPid]),
    
    % register processes (with PortNr as part of the name)
    DriverName = utils:process_name("ftp_driver_", PortNr),
    % if already registeres, unregister, then register again
    % this could happen, if the ftp_driver has crashed and must be restarted.
    case whereis(DriverName) of
	undefined ->
	    nothing; % not registered yet, so simply do nothing
	_OldPid ->
	    unregister(DriverName)
    end,
    register(DriverName, FtpDriverPid).


%% gets called as exit handler for crashing ftp_driver processes
driver_receive_loop_exit_handler(Pid, ExitReason) ->
    io:format("ftp_driver receive_loop (~p) crashed: ~p~n", [Pid, ExitReason]),
    
    case ExitReason of
	{error, Message, PortNr} ->
	    io:format("~w crashed on port: ~p~nMessage: ~p~n", ["\t\t",PortNr, Message]),	    
	    case get_connection_pid(PortNr) of
		undefined ->
		    io:format("error: ftp_connection process seems to be dead on port: ~p~n", [PortNr]),
		    exit("something went very wront here.");
		LoopPid ->
		    start_driver(PortNr, LoopPid)
	    end;
	
	Unknown ->
	    io:format("~w unknown error: ~p", ["\t\t",Unknown])
    end.


%% returns Pid for ftp_connection process tied to a given port.
get_connection_pid(PortNr) ->
    ProcName = utils:process_name(PortNr),
    whereis(ProcName).
