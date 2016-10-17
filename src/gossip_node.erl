
-module(gossip_node).
-include("gossip_config.hrl").
-include("gossip_message.hrl").

-export([run/1, data_manager/1, receiver/0, userver/1, epoch_manager/0, sender/3]).

-import(gossip_libtool, [findOneLongestWord/1, findLongestWords/1, removeDuplicateFromList/1, safeSendMsg/2, mergeDict/2, mergeFreqDict/2, convertToList/1,findValueInList/2,
						 findMostFrequent/1, hasWord/2, getWordFrequency/1, replaceNth/3, list_size/1]).

%% ====================================================================
%% API functions
%% ====================================================================

run(Config_file) ->
	%%% begin hang's code
	Lines = gossip_io:read_file_by_line(Config_file),
	case Lines of
		% error occurred when reading config file
		{error, Reason} ->
			erlang:exit({error, Reason});
		_ ->
			case read_all_configs(dict:new(),Lines) of
				{error, Reason} ->
					erlang:exit({error, Reason});
				{ok, Configure} ->
					case dict:find(?NODE_ID, Configure) of
						{ok, [Value|Rest]} ->
							% parse string to int
							case gossip_libtool:string_to_int(Value) of
								{error, Reason} ->
									erlang:exit({error, Reason});
								{ok, Val} ->
									erlang:put(?NODE_ID, Val)
							end;
						error ->
							erlang:exit({error, "Error: missing node id"})
					end,
					case dict:find(?NODE_HOME, Configure) of
						{ok, [Home|_]} ->
							erlang:put(?NODE_HOME, Home);
						{error, Reason_2} ->
							erlang:exit({error, Reason_2})
					end,
					case dict:find(?NODE_NEIGHBOR, Configure) of
						{ok, [Neighbor|_]} ->
							erlang:put(?NODE_NEIGHBOR, string:tokens(Neighbor, ?NODE_SEPERATOR));
						{error, Reason_3} ->
							erlang:exit({error, Reason_3})
					end,
					List_with_id = lists:map(fun(X)->
												case dict:find(X, Configure) of
													{ok, [Addr|_]} ->
														{list_to_atom(X), list_to_atom(Addr)};
													{error, Reason_4} ->
														erlang:exit({error, Reason_4})
												end
											 end
											, erlang:get(?NODE_NEIGHBOR)),
					List_with_addr = lists:map(fun(X)->
												case dict:find(X, Configure) of
													{ok, [Addr|_]} ->
														list_to_atom(Addr);
													{error, Reason_4} ->
														erlang:exit({error, Reason_4})
												end
											 end
											, erlang:get(?NODE_NEIGHBOR)),
					erlang:put(?NODE_NEIGHBOR_ID, List_with_id),
					erlang:put(?NODE_NEIGHBOR_ADDR, List_with_addr),
					Data_file = string:join([erlang:get(?NODE_HOME), ?NODE_DATA_FILE], "/"),
					Frag_list = read_fragments(Data_file),
					erlang:put(?NODE_FRAGLIST, Frag_list)
			end,
			
			%node address list
			NeighbourList = get(?NODE_NEIGHBOR_ADDR),
		
			%node fragment list
			FragmentList = get(?NODE_FRAGLIST),
			
			% start data manager process
			register(?DATA_MANAGER, spawn(?MODULE,data_manager,[FragmentList])),
			io:format("data_manager is started~n"),
	
			% start epoch manager
			register(?EPOCH_MANAGER, spawn(?MODULE, epoch_manager, [])),
			io:format("epoch_manager is started~n"),
			
			% start inactive process listening to node message
			register(?RECEIVER, spawn(?MODULE, receiver, [])),
			io:format("receiverProcName is started~n"),
	
			% start userver process listening to user query
			register(?USERVER, spawn(?MODULE, userver, [NeighbourList])),
			io:format("userverProcName is started~n")
		
	end.

epoch_manager() ->
	Epoch = #epoch{epoch_id = 0, cycle_remain = ?NODE_TEST_ITERATION},
	put(?NODE_EPOCH, Epoch),
	put(state, dead),
	epoch_manager_itr().

epoch_manager_itr() ->
	receive
		{query_epoch, Sender} ->
			Sender ! {epoch, get(?NODE_EPOCH), get(state)};
		{update_epoch, Epoch} ->
			put(?NODE_EPOCH, Epoch);
		{state, S} ->
			put(state, S)
		
	end,
	epoch_manager_itr().

userver(Neighbors) ->
	receive
		#mquery{qtype = longestWord, senderId = Sender, message = Msg } ->
			io:format("receive longestWord query~n"),
			register(?SENDER, spawn(?MODULE, sender, [longestWord, Neighbors,[]])),
			?EPOCH_MANAGER ! {state, alive},
			% wait for result
			receive
				epoch_finished ->
					?DATA_MANAGER ! {longestWord, self()},
					receive
						{longestWord, Longestwords} ->
							Sender ! #result{message=Longestwords}
					after 
							?timeout_const ->
						  		Sender ! #result{message=fail}
					end
			after 
					?timeout_const * ?NODE_TEST_ITERATION*2 ->
					io:format("query time out~n")
			end;
		#mquery{qtype = mostFreqWord, senderId = Sender, message = Msg } ->
			io:format("receive mostFreqWord query~n"),
			register(?SENDER, spawn(?MODULE, sender, [mostFreqWord, Neighbors,[]])),
			?EPOCH_MANAGER ! {state, alive},
			% wait for result
			receive
				epoch_finished ->
					?DATA_MANAGER ! {mostFreqWord, self()},
					receive
						{mostFreqWord, MostFreqWord} ->
							Sender ! #result{message=MostFreqWord}
					after 
							?timeout_const ->
						  		Sender ! #result{message=fail}
					end
			after 
					?timeout_const * ?NODE_TEST_ITERATION*2 ->
					io:format("query time out~n")
			end;
		#mquery{qtype = whichNodes, senderId = Sender, message = Msg } ->
			io:format("receive whichNodes query~n"),
			register(?SENDER, spawn(?MODULE, sender, [whichNodes, Neighbors, Msg])),
			?EPOCH_MANAGER ! {state, alive},

			% wait for result
			receive
				epoch_finished ->
					?DATA_MANAGER ! {whichNodes, Msg, self()},
					receive
						{whichNodes, Dict} ->
							List = mergeNodeList(Dict, Msg),
							Sender ! #result{message=List}
					after 
							?timeout_const ->
						  		Sender ! #result{message=fail}
					end
			after 
					?timeout_const * ?NODE_TEST_ITERATION*2 ->
					io:format("query time out~n")
			end;
		#mquery{qtype = updateFragment, senderId = Sender, message = Msg } ->
			io:format("receive update fragment query~n"),
			register(?SENDER, spawn(?MODULE, sender, [updateFragment, Neighbors, Msg])),
			?EPOCH_MANAGER ! {state, alive},

			% wait for result
			receive
				epoch_finished ->
					?DATA_MANAGER ! {fragment, erlang:element(1, Msg), self()},
					receive
						{fragment, Content} ->
							Sender ! #result{message=Content}
					after 
							?timeout_const ->
						  		Sender ! #result{message=fail}
					end
			after 
					?timeout_const * ?NODE_TEST_ITERATION*2 ->
					io:format("query time out~n")
			end;
		
		{start_sender, QType, DS} ->
			case QType of
				longestWord->
					register(?SENDER, spawn(?MODULE, sender, [longestWord, Neighbors, DS])),
					?EPOCH_MANAGER ! {state, alive};
				whichNodes->
					register(?SENDER, spawn(?MODULE, sender, [whichNodes, Neighbors, DS])),
					?EPOCH_MANAGER ! {state, alive};
				mostFreqWord->
					register(?SENDER, spawn(?MODULE, sender, [mostFreqWord, Neighbors, DS])),
					?EPOCH_MANAGER ! {state, alive};
				updateFragment->
					register(?SENDER, spawn(?MODULE, sender, [updateFragment, Neighbors, DS])),
					?EPOCH_MANAGER ! {state, alive}
			end;
		
		epoch_finished ->
			io:format("epoch finished~n");
		_->
			io:format("unknown message")
	end,
	userver(Neighbors).

mark_dict(Dict, [])->
	Dict;
mark_dict(Dict, [Head|Tail])->
	Dict2 = dict:store(Head, [node()], Dict),
	mark_dict(Dict2, Tail).

preCalculate(QType) ->
	case QType of
		longestWord ->
			WordList = lists:map(
						 fun(X)->
								 lists:nth(2, X)
						 end, get(?NODE_FRAGLIST)),
			LongestWordList = findLongestWords(convertToList(WordList)),
			put(longestWord, LongestWordList);
		mostFreqWord ->
			WordList = lists:map(
						 fun(X)->
								 lists:nth(2, X)
						 end, get(?NODE_FRAGLIST)),
			WordDict = getWordFrequency(convertToList(WordList)),
			{MostFreqWord, Freq} = findMostFrequent(WordDict),
			put(mostFreqWord, {WordDict, MostFreqWord, Freq});
		_ ->
			done
	end,
done.

data_manager(FragmentList) ->
	put(?NODE_FRAGLIST, FragmentList),
	preCalculate(longestWord),
	preCalculate(mostFreqWord),
	data_manager().

list_contain(Head, []) ->
	false;
list_contain(Head, [H|Tail]) ->
	case Head == H of
		true ->
			true;
		false ->
			list_contain(Head, Tail)
	end.
and_list([], List) ->
	[];
and_list([H1|Tail1], List) ->
	case list_contain(H1, List) of
		true ->
			[H1|and_list(Tail1, List)];
		false ->
			and_list(Tail1, List)
	end.
mergeNodeList_2(Dict, [], List) ->
	List;
mergeNodeList_2(Dict, [Head|Tail], List) ->
	case dict:find(Head, Dict) of
		error ->
			mergeNodeList_2(Dict, Tail, and_list([], List));
		{ok, Val} ->
			mergeNodeList_2(Dict, Tail, and_list(Val, List))
	end.
mergeNodeList(Dict, []) ->
	[];
mergeNodeList(Dict, [Head|Tail]) ->
	case dict:find(Head, Dict) of
		error ->
			mergeNodeList(Dict, Tail);
		{ok, Val} ->
			mergeNodeList_2(Dict, Tail, Val)
	end.

newMostFreq(OldWordDictTuple, NewWordDictTuple) ->
	PotentialMostFreq1 = findMostFrequent(element(1,OldWordDictTuple)),
	PotentialMostFreq2 = findMostFrequent(element(1,NewWordDictTuple)),
	TmpList = [{element(2,OldWordDictTuple),element(3,OldWordDictTuple)},{element(2,NewWordDictTuple),element(3,NewWordDictTuple)},
			   {element(1,PotentialMostFreq1),element(2,PotentialMostFreq1)},{element(1,PotentialMostFreq2),element(2,PotentialMostFreq2)}],
	SortedTmpList = lists:sort(Fun = fun(A, B) ->
			element(2,A)>element(2,B)
					 end,  TmpList),
	NewWordDict = mergeFreqDict(element(1,OldWordDictTuple),element(1,NewWordDictTuple)),
	NewMostFreq = {NewWordDict, element(1,lists:nth(1, SortedTmpList)), element(2,lists:nth(1, SortedTmpList))},
	NewMostFreq.

find_fragment(ID, []) ->
	none;
find_fragment(ID, [H|Tail]) ->
	case ID == lists:nth(1, H) of
		true ->
			lists:nth(2, H);
		false ->
			find_fragment(ID, Tail)
	end.

data_manager() ->
	receive 
		{longestWord, Sender}->
			Sender ! {longestWord,get(longestWord)};
		{update_longestWord, LongestWordList} ->
			NewLongestWordList = findLongestWords(removeDuplicateFromList(lists:append(get(longestWord), LongestWordList))),
			put(longestWord, NewLongestWordList);
		{whichNodes, Msg, Sender} ->
			Dict = get(whichNodes),
			case Dict of
				undefined ->
					WordList = convertToList(lists:map(
						 fun(X)->
								 lists:nth(2, X)
						 end, get(?NODE_FRAGLIST))),
					HitDict = mark_dict(dict:new(), and_list(Msg,WordList)),
					put(whichNodes ,HitDict),
					Sender ! {whichNodes, HitDict};
				_->
					Sender ! {whichNodes, get(whichNodes)}
			end;
		{update_whichNodes, NDict} ->
			Dict = get(whichNodes),
			case Dict of
				undefined ->
					put(whichNodes, NDict);
				_->
					Dict2 = dict:merge(
							  fun(_, Val, Val2) ->
									  lists:umerge(lists:sort(Val), lists:sort(Val2))
							  end, Dict, NDict),
					put(whichNodes, Dict2)
			end;
		{mostFreqWord, Sender} ->
			Sender ! {mostFreqWord, get(mostFreqWord)};
		{update_mostFreqWord, Data} ->
			Newmostfreq = newMostFreq(get(mostFreqWord), Data),
			put(mostFreqWord, Newmostfreq);
		{fragments, Sender} ->
			Sender ! {fragments, get(?NODE_FRAGLIST)};
		{fragment, ID, Sender}->
			Frag = find_fragment(ID, get(?NODE_FRAGLIST)),
			Sender ! {fragment, Frag};
		{updateFragment, ID, Content} -> 
			NewFrag = lists:map(
						fun(X)->
								Id = lists:nth(1, X),
								case ID==Id of
									true ->
										io:format("correct~n"),
										[ID,Content];
									false ->
										X
								end
						end, get(?NODE_FRAGLIST)),
			put(?NODE_FRAGLIST, NewFrag),
			preCalculate(longestWord),
			preCalculate(mostFreqWord)
	end,
	data_manager().

update_epoch(Nepoch, State) ->
	?EPOCH_MANAGER ! {update_epoch, Nepoch},
	?EPOCH_MANAGER ! {state, State}.

update_epoch(Nepoch) ->
	?EPOCH_MANAGER ! {update_epoch, Nepoch}.

updateLocal(QType, Msg) ->
	case QType of
		longestWord ->
			?DATA_MANAGER ! {update_longestWord, Msg};
		whichNodes ->
			?DATA_MANAGER ! {update_whichNodes, erlang:element(2, Msg)};
		mostFreqWord ->
			?DATA_MANAGER ! {update_mostFreqWord, Msg};
		updateFragment ->
			case element(3, Msg) == node() of
				true->
					done;
				false ->
					?DATA_MANAGER ! {updateFragment, element(1, Msg), element(2, Msg)}
			end;
		_ ->
			done
	end,
done.

preprocess(QType, Neighbors, DS) ->
	case QType of
		whichNodes ->
			?DATA_MANAGER ! {fragments, self()},
			receive
				{fragments, Node_fraglist}->
					WordList = convertToList(lists:map(
						fun(X)->
							lists:nth(2, X)
						end, Node_fraglist)),
						HitDict = mark_dict(dict:new(), and_list(DS,WordList)),
					?DATA_MANAGER ! {whichNodes, DS, self()},
					receive
						{whichNodes, Dict} ->
							Dict2 = dict:merge(
							fun(_, Val, Val2) ->
								lists:umerge(lists:sort(Val), lists:sort(Val2))
							end, Dict, HitDict),
						?DATA_MANAGER ! {update_whichNodes, Dict2},
							put(preprocessed, true)
					end
			end;		
		updateFragment ->
			?DATA_MANAGER ! {updateFragment, element(1, DS), element(2, DS)},
			put(preprocessed, true);
		_->
			put(preprocessed, true)
	end.

sender(QType, Neighbors, DS) ->
	case get(preprocessed) of
		undefined ->
			preprocess(QType, Neighbors, DS);
		_->
			done
	end,
	?EPOCH_MANAGER ! {query_epoch, self()},
	receive
		{epoch, Epoch, State} ->
			case State of
				alive ->
					senderSendMsg(QType, Neighbors, Epoch, DS),
					% await for reply
					receive
						#badepoch{dead=true, epoch=Responser_epoch} ->
							io:format("dead true~p ~p~n",[Epoch#epoch.epoch_id, Responser_epoch#epoch.epoch_id]),
							NewEpoch = #epoch{epoch_id = Responser_epoch#epoch.epoch_id, cycle_remain = Responser_epoch#epoch.cycle_remain},
							update_epoch(NewEpoch, dead),
							io:format("sender end, leave epoch~n"),
							erlang:exit(normal);
						#badepoch{dead=false, epoch=_} ->
							io:format("dead false~n"),
							case Epoch#epoch.cycle_remain > 0 of
								true ->
									NewEpoch = #epoch{epoch_id=Epoch#epoch.epoch_id, cycle_remain=Epoch#epoch.cycle_remain-1},
									update_epoch(NewEpoch);
								false ->
									NewEpoch = #epoch{epoch_id=Epoch#epoch.epoch_id+1, cycle_remain=?NODE_TEST_ITERATION},
									update_epoch(NewEpoch),
									?EPOCH_MANAGER !{state, dead},
									?USERVER ! epoch_finished,
									exit(normal)
							end;
						#pRepmessage{qtype=QType, senderId=_, epoch=_, message=Msg} ->
							updateLocal(QType, Msg),
							case Epoch#epoch.cycle_remain > 0 of
								true ->
									io:format("~p~n", [Epoch#epoch.cycle_remain]),
									NewEpoch = #epoch{epoch_id=Epoch#epoch.epoch_id, cycle_remain=Epoch#epoch.cycle_remain-1},
									update_epoch(NewEpoch);
								false ->
									NewEpoch = #epoch{epoch_id=Epoch#epoch.epoch_id+1, cycle_remain=?NODE_TEST_ITERATION},
									update_epoch(NewEpoch),
									?EPOCH_MANAGER !{state, dead},
									?USERVER ! epoch_finished,
									exit(normal)
							end
					end;
				dead -> 
					done
			end
	end,
	receive
	after
			?timeout_const ->
				sender(QType, Neighbors, DS)
	end.

getQueryLocalData(QType, DS) ->
	case QType of
		longestWord ->
			?DATA_MANAGER ! {longestWord, self()},
			receive
				{longestWord, WordList} ->
					WordList
			end;
		whichNodes ->
			?DATA_MANAGER ! {whichNodes, DS, self()},
			receive
				{whichNodes, Dict} ->
					{DS,Dict}
			end;
		mostFreqWord ->
			?DATA_MANAGER ! {mostFreqWord, self()},
			receive
				{mostFreqWord, Data} ->
					Data
			end;
		updateFragment ->
			case erlang:tuple_size(DS) < 3 of
				true ->
					{element(1,DS), element(2,DS), node()};
				false ->
					DS
			end
	end.

senderSendMsg(QType, AddrList, Epoch, DS) ->
	Identity = #identity{responser_name = self(),responser_address = node()},
	Msg = #pmessage{qtype = QType, senderId = Identity, epoch = Epoch, message = getQueryLocalData(QType, DS)},	
	RandomIdx = random:uniform(list_size(AddrList)),
	% send message
	{?RECEIVER, lists:nth(RandomIdx, AddrList)} ! Msg.

receiverSendMsg(QType, ADDR, Epoch, DS) ->
	case QType of
		whichNodes ->
			Identity = #identity{responser_name = self(),responser_address = node()},
			Msg = #pRepmessage{qtype = QType, senderId = Identity, epoch = Epoch, message = getQueryLocalData(QType,erlang:element(1, DS))},	
			{?SENDER, ADDR} ! Msg;
		_->
			Identity = #identity{responser_name = self(),responser_address = node()},
			Msg = #pRepmessage{qtype = QType, senderId = Identity, epoch = Epoch, message = getQueryLocalData(QType,DS)},	
			{?SENDER, ADDR} ! Msg
	end.

checkEpochStateId(MyEpoch, InComeEpoch) ->
	MyEpochId = MyEpoch#epoch.epoch_id,
	InEpochId = InComeEpoch#epoch.epoch_id,
	if
		MyEpochId > InEpochId ->
			larger;
		true ->
			if
				MyEpochId == InEpochId ->
					equal;
				true ->
					smaller
			end
	end.

receiver() ->
	receive 
		#pmessage{qtype = QType, senderId = #identity{responser_name = PID,responser_address = NADDR}, epoch = IncomeEpoch, message = Msg} ->
			?EPOCH_MANAGER ! {query_epoch, self()},
			receive
				{epoch, Epoch, State} ->
					case State of
						alive ->
							case checkEpochStateId(Epoch, IncomeEpoch) of
								equal ->
									receiverSendMsg(QType, NADDR, Epoch, Msg),
									updateLocal(QType, Msg);
								larger ->
									{PID, NADDR} ! #badepoch{dead=true, epoch=Epoch};
								smaller ->
									{PID, NADDR} ! #badepoch{dead=false, epoch=Epoch}
							end;
						dead ->
							case checkEpochStateId(Epoch, IncomeEpoch) of
								equal ->
									NewEpoch = #epoch{epoch_id=Epoch#epoch.epoch_id, cycle_remain=?NODE_TEST_ITERATION},
									update_epoch(NewEpoch),
									case QType of
										whichNodes ->
											?USERVER ! {start_sender, QType, erlang:element(1, Msg)};
										updateFragment ->
											?USERVER ! {start_sender, QType, {element(1,Msg), element(2,Msg)}};
										_->
											?USERVER ! {start_sender, QType, Msg}
									end,
									receiverSendMsg(QType, NADDR, NewEpoch, Msg),
									updateLocal(QType, Msg);
								larger ->
									{?SENDER, NADDR} ! #badepoch{dead=true, epoch=Epoch};
								smaller ->
									{?SENDER, NADDR} ! #badepoch{dead=false, epoch=Epoch}
							end
					end
			end;
		_ ->
			io:format("unknown message")
	end,
	receiver().

%% ====================================================================
%% Internal functions
%% ====================================================================
read_all_configs(Dict, []) ->
	{ok, Dict};
read_all_configs(Dict, [Line|Lines]) ->
	Tokens = string:tokens(Line, ?SEPERATOR),
	case gossip_libtool:list_size(Tokens) of
		2 ->
			Dict2 = dict:append(lists:nth(1, Tokens), lists:nth(2, Tokens), Dict),
			read_all_configs(Dict2, Lines);
		_ ->
			{error, "ERROR: invalid file structure"}
	end.


parse_fragment([]) ->
	[];
parse_fragment([_]) ->
	[];
parse_fragment([ID, Content|Rest]) ->
	%%[[string:to_integer(ID), string:tokens(Content, " ")]]++parse_fragment(Rest).
	[[ID, string:tokens(Content, " ")]]++parse_fragment(Rest).

read_fragments(F_path) ->
	Lines = gossip_io:read_file_by_line(F_path),
	case Lines of
		{error, Reason} ->
			{error, Reason};
		_ ->
			parse_fragment(Lines)
	end.

seperate_list([]) ->
	{[],[]};
seperate_list([[A,B] | Tail]) ->
	{ID_LIST, CONTENT_LIST} = seperate_list(Tail),
	{ID_LIST++[element(1,string:to_integer(A))], CONTENT_LIST++[B]}.

parse_data(Raw_data) ->
	Word_list = string:tokens(Raw_data, string:join([" "|?punctuation_const], "")),
	lists:map(fun(X)->string:to_lower(X) end, Word_list).

