%%% Name: gossip_user_interface.hrl
%%% Project: Gossip System
%%%	Author: Hang Gao
%%% Description: This is where the user interfaces should be. 

-module(gossip_user_interface).
-include("gossip_config.hrl").
-include("gossip_message.hrl").

%% ====================================================================
%% API functions
%% ====================================================================
-export([find_longest_word/1, which_nodes/2, most_freq_word/1,update_fragment/3]).

%%% ---- find_longest_word ----
%%% Description: find the longest word in file F.
%%% Requirement:
%%%			1. send request to the userver process of target node
%%%			2. starts receive for message
%%%			3. return the received message

find_longest_word(Node_addr)->
	timer:tc(
	  fun()->
			register(user_interface, self()),	
			Query = #mquery{qtype=longestWord, senderId={user_interface,node()}, message=[] },
			{userverProcName, Node_addr} ! Query,
			io:format("query sent~n"),
			receive
				#result{message=Msg} ->
					case Msg of
						fail ->
						    io:format("query failed~n");
						_->
							io:format("["),
							lists:foreach(
			 					 fun(X) ->
									  io:format("~p, ", [X])
			  					 end, Msg),
							io:format("]~n")
					end;
				_->
		 			io:format("unknown reply")
			end,
			erlang:unregister(user_interface) end).

which_nodes(Node_addr, WordList) ->
	timer:tc(
	  fun()->
			register(user_interface, self()),	
			Query = #mquery{qtype=whichNodes, senderId={user_interface,node()}, message=WordList },
			{userverProcName, Node_addr} ! Query,
			io:format("query sent~n"),
			receive
				#result{message=Msg} ->
					case Msg of
						fail ->
						    io:format("query failed~n");
						_->
							io:format("["),
							lists:foreach(
			 					 fun(X) ->
									  io:format("~p, ", [X])
			  					 end, Msg),
							io:format("]~n")
					end;
				_->
		 			io:format("unknown reply")
			end,
			erlang:unregister(user_interface) end).



most_freq_word(Node_addr)->
	timer:tc(
	  fun()->
			register(user_interface, self()),	
			Query = #mquery{qtype=mostFreqWord, senderId={user_interface,node()}, message=[] },
			{userverProcName, Node_addr} ! Query,
			io:format("query sent~n"),
			receive
				#result{message=Msg} ->
					io:format("~p~n", [erlang:element(2, Msg)]);
				_->
		 			io:format("unknown reply")
			end,
			erlang:unregister(user_interface) end).

update_fragment(Node_addr, ID, Content) ->
	timer:tc(
	  fun()->
			register(user_interface, self()),	
			Query = #mquery{qtype=updateFragment, senderId={user_interface,node()}, message={ID, Content} },
			{userverProcName, Node_addr} ! Query,
			io:format("query sent~n"),
			receive
				#result{message=Msg} ->
					io:format("~p~n", [Msg]);
				_->
		 			io:format("unknown reply")
			end,
			erlang:unregister(user_interface)  end).
	
%% ====================================================================
%% Internal functions
%% ====================================================================


