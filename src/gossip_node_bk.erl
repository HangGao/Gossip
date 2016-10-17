%%% Name: gossip_node.hrl
%%% Project: Gossip System
%%%	Author: Guohao Zhang
%%% ########################################################################################

-module(gossip_node_bk).
-include("gossip_config.hrl").
-include("gossip_message.hrl").

%% ====================================================================
%% API functions
%% ====================================================================
-export([run/1, userver/2, receiver/1, sender/3]).

-import(gossip_libtool, [findOneLongestWord/1, findLongestWords/1, removeDuplicateFromList/1, safeSendMsg/2, mergeDict/2, mergeFreqDict/2, convertToList/1,findValueInList/2,
						 findMostFrequent/1, hasWord/2, getWordFrequency/1, replaceNth/3, list_size/1]).

%%%--- run -----
%%% Description: it should be the only interface public. Each node should run in a sandbox.
%%% Requirement:
%%%			1. Read config file and read fragment data file
%%%			2. Set up all inner datastructures used by server and client
%%%			3. spawn a new process as userver that responses to user interface request.
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
														[X, Addr];
													{error, Reason_4} ->
														erlang:exit({error, Reason_4})
												end
											 end
											, erlang:get(?NODE_NEIGHBOR)),
					List_with_addr = lists:map(fun(X)->
												case dict:find(X, Configure) of
													{ok, [Addr|_]} ->
														Addr;
													{error, Reason_4} ->
														erlang:exit({error, Reason_4})
												end
											 end
											, erlang:get(?NODE_NEIGHBOR)),
					erlang:put(?NODE_NEIGHBOR_ID, List_with_id),
					erlang:put(?NODE_NEIGHBOR_ADDR, List_with_addr),
					Data_file = string:join([erlang:get(?NODE_HOME), ?NODE_DATA_FILE], "/"),
					Frag_list = seperate_list(read_fragments(Data_file)),
					erlang:put(?NODE_FRAGLIST, Frag_list)
			end
	end,
	%%% end Hang's code
	
	%node address list
	NeighbourList = get(?NODE_NEIGHBOR_ADDR),
	%node fragment ID list
	FragmentList = element(1,get(?NODE_FRAGLIST)),
	io:format("test fragid list: ~p\n",[lists:nth(1,FragmentList)]),
	%node fragment content list
	WordLists = element(2,get(?NODE_FRAGLIST)),
	
	
%% 	NeighbourList = [node()],
%% 	
%% 	FragmentList = [1, 2],
%% 	WordLists = [["asdfsdaf","adsf","dsfasdfasd","asdfsadf","asdfasdfsad"],
%%   				 ["adsfsad","sdfasdfsadf","dsfa","adsf","sadf"]
%%   				],

	% longest word command
	LongestWordList = [],

	% which command
	HitDict = dict:new(),
	
	% create intitial epoch state with epoch number 0 and reman cycle ?node_test_iteration
	EpochState = #epoch{epoch_id = 0, cycle_remain = ?NODE_TEST_ITERATION},
	
	% word and its frequency
	WordDict = dict:new(),

	MostFreqWord = "",
	DS = [	NeighbourList, 
			FragmentList, 
			WordLists, 
			EpochState, 
			
			%%% these are DS for query part
			LongestWordList, 
			HitDict, 
			{WordDict, MostFreqWord, 0}
		 ],
	register(userverProcName, spawn(?MODULE,userver,[DS, 1])),

	done.

%% ====================================================================
%% Internal functions
%% ====================================================================

%%%--- userver ----
%%% Description: It is the routine for a userver process. A server process listen to user interface and inner communication.
%%% Input: ds: all state that should be kept as the inner globol aggragation state, including  {all aggregation value}, 
%%%				{fragment ID, fragment content list}.
%%% Requirements:
%%%			1. always keep looping
%%%			2. handle all kinds of requests.
%%%			3. wait for user query, upon receiving one:
%%%			4. Initialize a new epoch:
%%%					a. spawn a new process as the server that keeps receiving new messages
%%%					b. register a name for the server
%%%					c. spawn a new process as the client that repeatedly send messages in some time interval.
%%%					d. register a name for that client process 
%%%			5. Waiting for inner message indicating the end of epoch and write all states into file system.
%%%			6. go back to step 3

userver(DS, N) ->
	% put DS into process dictionary with key ele0
	putDS(DS),
		%io:format("~p\n",[?LINE]),
	% spawn and register receiver with DS
	register( receiverProcName, spawn(?MODULE, receiver, [DS])),
		%io:format("~p\n",[?LINE]),

	userver(N).

userver(N) ->
	receive
		%%% -- receive request from user as a query ---
		#mquery{qtype = QType, senderId = Sender, message = Msg } ->
			%%% --- save the sender addr ---
			put(currentSender,Sender),
			put(currentQueryType,QType),
			
			%%% --- update epoch ---
			Epoch = getEpochState(getDS()),
			% start a new epoch
			NewEpoch = #epoch{epoch_id = Epoch#epoch.epoch_id+1, cycle_remain = ?NODE_TEST_ITERATION},
			% replace epoch state
			NewDS = replaceNth(4,getDS(),NewEpoch),
			% store new ds
			putDS(NewDS),
				%io:format("User Query ~p Received.\n",[QType]),
				%io:format("user query ~p ~p\n",[Epoch#epoch.epoch_id,?LINE]),
			

			%%% broadcast query
			MsgToBeSent = #broadcastQuery{epoch=NewEpoch, queryContent=#mquery{qtype = QType, senderId = Sender, message = Msg }},
			broadcastMsg(MsgToBeSent),
			
			%%% if it is updateMsg, do the update
			case QType of
				updateFragment ->
					updateLocalFragment(Msg, getDS()),
					done;
				_ ->
					% forward user's query to receiverProcName
					receiverProcName ! #receiverResponse{qtype = QType, message = Msg},
					% regist a new process for sending messages
					register( senderProcName,spawn(?MODULE, sender, [getDS(), QType, Msg]))
			end;
		
			%%% --- call some query handler ----	

		%%% --- receive broadcast query ---
		#broadcastQuery{epoch=Epoch, queryContent=#mquery{qtype = QType, senderId = Sender, message = Msg }} ->
			io:format("broadCast: ~p ~p\n",[Epoch#epoch.epoch_id,?LINE]),
			case checkEpochStateId(Epoch, getDS()) of
				smaller ->
					put(currentSender,Sender),
					put(currentQueryType,QType),
					NewDS = replaceNth(4,getDS(),Epoch),
					putDS(NewDS),
					put(currentSender,Sender),
					

				%%% broadcast query
				BroadCastMsg = #broadcastQuery{epoch=Epoch, queryContent=#mquery{qtype = QType, senderId = Sender, message = Msg }},
				broadcastMsg(BroadCastMsg),
						
				%%% if it is updateMsg, do the update
				case QType of
					updateFragment ->
						updateLocalFragment(Msg, getDS()),
						done;
					_ ->
						receiverProcName ! #receiverResponse{qtype = QType, message = Msg},
						register( senderProcName, spawn(?MODULE, sender, [getDS(), QType, Msg]))
						
				end;
				%io:format("~p\n",[?LINE]);
				larger ->
					done;
				equal ->
					done
			end;
		%%% -- this is for test only ---
		testLongestWord ->
			QType = longestWord,
			Msg = "",
			io:format("test Query ~p Received.\n",[QType]),
			safeSendMsg(userverProcName, #mquery{qtype = QType, senderId = #identity{responser_name = self(),responser_address = node()}, message = Msg });
		
		{testWhichNodes, WordList} ->
			QType = whichNodes,
			Msg = WordList,
			io:format("test Query ~p Received.\n",[QType]),
			safeSendMsg(userverProcName, #mquery{qtype = QType, senderId = #identity{responser_name = self(),responser_address = node()}, message = Msg });
		
		testMostFreq ->
			QType = mostFreqWord,
			Msg = "",
			io:format("test Query ~p Received.\n",[QType]),
			safeSendMsg(userverProcName, #mquery{qtype = QType, senderId = #identity{responser_name = self(),responser_address = node()}, message = Msg });
		
		{testUpdateFragment, {FragId, Words}} ->
			QType = updateFragment,
			Msg = Words,
			io:format("test Query ~p Received.\n",[QType]),
			safeSendMsg(userverProcName, #mquery{qtype = QType, senderId = #identity{responser_name = self(),responser_address = node()}, message = {FragId, Words} });
		%%% -- test only ends

		%%% -- receive message from inner process ---
		%%%#pmessage{qtype = QType, senderId=#identity{responser_name=Rname, responser_address=Raddr}, message=Msg} ->
		#pmessage{qtype = QType, senderId=Sender, message=Msg} ->
				%%% stops all current processes
			io:format("Stop all Message Received\n"),
				%%%safeSendMsg(receiverProcName,finished),
			% tell sender process to finish
			safeSendMsg(senderProcName,finished),
			case QType of
				smaller ->
					io:format("Outdated, killed.\n");
					%%userverProcName ! #mquery{qtype = QType, senderId = Sender, message = Msg };
				_ ->
					io:format("Result: ~p\n",[Msg])
			end;
		
		current ->
			% output result of query
			io:format("Result: ~p\n",[getQueryLocalData(get(currentQueryType))]);
		
		% receive finished message to abort both receiver and sender
		finished ->	
			safeSendMsg(receiverProcName,finished),
			safeSendMsg(senderProcName,finished),
			
			receiverProcName ! #userverQuery{qtype = get(currentQueryType), message = getQueryLocalData(get(currentQueryType))},
			
			io:format("Epoch Ends\n");
		_ ->
			io:format("unknown msg at ~p",[?LINE])
%% 	after 
%% 		?timeout_const ->
%% 			if
%% 				N >= 1 ->
%% 					{userverProcName, node()} ! #mquery{qtype = longestWord, senderId=#identity{responser_name=self(), responser_address=node()}, message=""};
%% 				true ->
%% 					done
%% 			end
 	end,
	userver(max(N-1,0)).

%%%--- server ----
%%% Description: It is the routine for a server process. A server process listen to its neighbor nodes, itself.
%%% Input: ds: all state that should be kept as the inner globol gossip state, including {epoch_id, cycyles}, {all aggregation value}, 
%%%				{fragment ID, fragment content list}.
%%% Requirements:
%%%			1. keep looping
%%%			2. handle all kinds of requests.
%%%			3. keep monitoring current epoch state. alert the init process if it ends and stop listening to requests.
receiver(DS) ->
	putAll(DS),
		%io:format("~p\n",[?LINE]),
	receiver().
receiver() ->
	receive
		%%% -- receive message from other nodes as "pmessage" record
			%%% --- pmessage handler-> check if it is a request or a reply, do something different
			%%% update DS by the return of handler. !!!!important, must update all DS states within this function, it ensures consistency.

		
		#receiverResponse{qtype = QType, message = Msg} ->
				%io:format("~p\n",[?LINE]),
			preCalculate(QType, Msg);
				%io:format("~p\n",[?LINE]);
		
		%%% receive initiator's query
		#pmessage{qtype = QType, senderId = Identity, epoch = EpochState, message = Msg} ->
					%%% reply a message
					Reply = #pRepmessage{qtype = QType, senderId=getSelfIdentity(), epoch=EpochState, message = getQueryLocalData(QType)},
					{receiverProcName, Identity#identity.responser_address} ! Reply,
					%%% update local data
					updateLocal(QType, Msg);
		%%% reveive a reply
		#pRepmessage{qtype = QType, senderId=Identity, epoch=EpochState, message = Msg} ->
					%%% do not need to reply
					%%% update local data
					updateLocal(QType, Msg);
		
		
		#userverQuery{qtype = QType, message = Msg} ->
			userverProcName ! #userverQuery{qtype = QType, message = getQueryLocalData(QType)};

		finished ->
			io:format("receiver is finished.\n"),
			exit(normal);
		_ ->
			io:format("unknown msg at ~p",[?LINE])

	end,
	%%% reenter into the loop
	receiver().


%%% --- client ----
%%% Description: It is the routine for a client process. A client process simply select a neighbor to communicate within a single cycle
%%% Input: ds: all state that should be used to finish the task of a client, including a list of neighbors, the type of aggregation and so on.
%%% Requirements:
%%%			1. keep looping
%%%			2. use pair selection to choose a neighbor
%%%			3. Send inner message to server process indicating the start of protocol communication request
%%%			4. Send message to that neighbor
sender(DS, QType, Msg) ->
	putAll(DS),
	preCalculate(QType, Msg),
	sender(QType).
sender(QType) ->
	%%% do something

	%%% choose all neighbours from the nrighbour list
	Neighbor_Map = getNeighbourList(),
	%%% send mesg to that chosen neighbour
	senderSendMsg(QType, Neighbor_Map),

	%%% reexecute the routine again after timeout milliseconds

	updateEpoch(),
	
	%%% if epoch_remain <= 0, send stop all msg
	checkEpochStateRemains(QType,getQueryLocalData(QType)),
	
	receive
		finished ->
			io:format("sender is finished.\n"),
			exit(normal);
		
		#pmessage{qtype = QType, senderId = Identity, epoch = EpochState, message = Msg} ->
			updateSenderCopy(QType, Msg);
			%%%io:format("sender epoch remains: ~p\n",[EpochState#epoch.cycle_remain]);
		
		_ ->
			io:format("unknown msg at ~p",[?LINE])
	after 
		?timeout_const ->
			done
	end,
	sender(QType).


getDS() ->
	get(ele0).
putDS(DS) ->
	put(ele0, DS).

getNeighbourList(DS)->
	lists:nth(1, DS).
getNeighbourList()->
	get(ele1).
putNeighbourList(N)->
	put(ele1, N).

getFragmentList(DS)->
	lists:nth(2, DS).
getFragmentList()->
	get(ele2).
putFragmentList(N)->
	put(ele2, N).


getWordLists(DS)->
	lists:nth(3, DS).
getWordLists()->
	get(ele3).
putWordLists(N)->
	put(ele3, N).


getEpochState(DS)->
	lists:nth(4, DS).
getEpochState()->
	get(ele4).
putEpochState(N)->
	put(ele4, N).


getLongestWordList(DS)->
	lists:nth(5, DS).
getLongestWordList()->
	get(ele5).
putLongestWordList(N)->
	put(ele5, N).


getHitDict(DS)->
	lists:nth(6, DS).
getHitDict()->
	get(ele6).
putHitDict(N)->
	put(ele6, N).


getMostFreq(DS)->
	lists:nth(7, DS).
getMostFreq()->
	get(ele7).
putMostFreq(N)->
	put(ele7, N).

putAll(DS) ->
	put(ele1, lists:nth(1, DS)),
	put(ele2, lists:nth(2, DS)),
	put(ele3, lists:nth(3, DS)),
	put(ele4, lists:nth(4, DS)),
	put(ele5, lists:nth(5, DS)),
	put(ele6, lists:nth(6, DS)),
	put(ele7, lists:nth(7, DS)),
done.

preCalculate(QType, Msg) ->
	case QType of
		longestWord ->
			LongestWordList = findLongestWords(convertToList(getWordLists())),
			putLongestWordList(LongestWordList);
		whichNodes ->
			WordList = convertToList(getWordLists()),
			HitDict = hasWord(Msg, WordList),
			putHitDict(HitDict);
		mostFreqWord ->
			WordList = convertToList(getWordLists()),
			WordDict = getWordFrequency(WordList),
			{MostFreqWord, Freq} = findMostFrequent(WordDict),
			putMostFreq({WordDict, MostFreqWord, Freq});
		_ ->
			done
	end,
done.

updateLocal(QType, Msg) ->
	case QType of
		longestWord ->
			updateLongestWordList(getLongestWordList(), Msg);
		whichNodes ->
			updateHitDict(getHitDict(), Msg);
		mostFreqWord ->
			updateMostFreq(getMostFreq(), Msg);
		_ ->
			done
	end,
done.

updateSenderCopy(QType, Msg) ->
	case QType of
		longestWord ->
			putLongestWordList(Msg);
		whichNodes ->
			putHitDict(Msg);
		mostFreqWord ->
			putMostFreq(Msg);
		_ ->
			done
	end,
done.

updateEpoch() ->
	OleEpoch = getEpochState(),
	EpochState =  #epoch{epoch_id = OleEpoch#epoch.epoch_id, cycle_remain = OleEpoch#epoch.cycle_remain-1},
	putEpochState(EpochState).
	
updateLongestWordList(OldLongestWordList, LongestWordList) ->
	NewLongestWordList = findLongestWords(removeDuplicateFromList(lists:append(OldLongestWordList, LongestWordList))),
	Identity = #identity{responser_name = self(), responser_address = node()},
	Msg =  #pmessage{qtype = longestWord, senderId = Identity, epoch = getEpochState(), message = LongestWordList},
	%% update the copy of sender proc
	safeSendMsg(senderProcName, Msg),
	putLongestWordList(NewLongestWordList).

updateHitDict( OldHitDict, HitDict) ->
	NewHitDict = mergeDict(OldHitDict, HitDict),
	Identity = #identity{responser_name = self(), responser_address = node()},
	Msg =  #pmessage{qtype = whichNodes, senderId = Identity, epoch = getEpochState(), message = NewHitDict},
	%% update the copy of sender proc
	safeSendMsg(senderProcName, Msg),
	putHitDict(NewHitDict).

updateMostFreq(OldWordDictTuple, NewWordDictTuple) ->
%% 	io:format("Old Input: ~p\n",[OldWordDictTuple]),
%% 	io:format("New Input: ~p\n",[NewWordDictTuple]),
	PotentialMostFreq1 = findMostFrequent(element(1,OldWordDictTuple)),
	PotentialMostFreq2 = findMostFrequent(element(1,NewWordDictTuple)),
	TmpList = [{element(2,OldWordDictTuple),element(3,OldWordDictTuple)},{element(2,NewWordDictTuple),element(3,NewWordDictTuple)},
			   {element(1,PotentialMostFreq1),element(2,PotentialMostFreq1)},{element(1,PotentialMostFreq2),element(2,PotentialMostFreq2)}],
	SortedTmpList = lists:sort(Fun = fun(A, B) ->
			element(2,A)>element(2,B)
					 end,  TmpList),
	NewWordDict = mergeFreqDict(element(1,OldWordDictTuple),element(1,NewWordDictTuple)),
%% 	io:format("Input1: ~p\n",[element(1,OldWordDictTuple)]),
%% 	io:format("Input2: ~p\n",[element(1,NewWordDictTuple)]),
	NewMostFreq = {NewWordDict, element(1,lists:nth(1, SortedTmpList)), element(2,lists:nth(1, SortedTmpList))},
	Identity = #identity{responser_name = self(), responser_address = node()},
	Msg =  #pmessage{qtype = mostFreqWord, senderId = Identity, epoch = getEpochState(), message = NewMostFreq},
	%% update the copy of sender proc
	safeSendMsg(senderProcName, Msg),
	putMostFreq(NewMostFreq).

checkEpochStateRemains(QType, Msg) ->
	NewEpochState = getEpochState(),
	%%%io:format("receiver epoch remains: ~p\n",[NewEpochState#epoch.cycle_remain]),
	if
		NewEpochState#epoch.cycle_remain =< 0 ->
			StopReqMsg = #pmessage{qtype = QType, senderId = #identity{responser_name = self(), responser_address = node()}, epoch = NewEpochState, message = Msg},
			safeSendMsg(userverProcName, StopReqMsg);
		true ->
			done
	end.

checkEpochStateId(InComeEpoch, DS) ->
	MyEpoch = getEpochState(DS),
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

checkEpochStateId(InComeEpoch) ->
	MyEpoch = getEpochState(),
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

getQueryLocalData(QType) ->
	case QType of
		longestWord ->
			getLongestWordList();
		whichNodes ->
			getHitDict();
		mostFreqWord ->
			getMostFreq()
	end.

senderSendMsg(QType, AddrList) ->
	EpochState =  getEpochState(),
	Identity = #identity{responser_name = self(),responser_address = node()},
	
	Msg = #pmessage{qtype = QType, senderId = Identity, epoch = EpochState, message = getQueryLocalData(QType)},
	
	RandomIdx = random:uniform(list_size(AddrList)),
	
	{receiverProcName, list_to_atom(lists:nth(RandomIdx, AddrList))} ! Msg.

%% 	SenderFunc = fun(NeighbourAddr) ->
%%  			{receiverProcName, list_to_atom(NeighbourAddr)} ! Msg
%% %%			{receiverProcName, 'node_1@127.0.0.1' } ! Msg
%% 		end,
%% 	lists:foreach(SenderFunc, AddrList).


updateLocalFragment(Msg, DS) ->
	Index = element(1,Msg),
	NewWordList = parse_data(element(2,Msg)),
	OldWordLists = getWordLists(DS),
	FragList = getFragmentList(DS),
	io:format("My Fragment list ~p\n",[FragList]),
	N =  findValueInList(FragList,Index),
	case N of
		0 ->
			io:format("Do not have fragment ~p, igored.\n",[Index]),
			done;
		_ ->
			NewWordLists = replaceNth(N,OldWordLists,NewWordList),
			NewDS = replaceNth(3, getDS(), NewWordLists),
			putDS(NewDS),
			io:format("New fragments here: ~p\n",[NewWordLists])
	end,
	done.

getSelfIdentity() ->
	#identity{responser_name = self(),responser_address = node()}.

broadcastMsg(Msg) ->
			SenderFunc = fun(NeighbourAddr) ->
						{userverProcName, list_to_atom(NeighbourAddr)} ! Msg
			end,
			lists:foreach(SenderFunc, getNeighbourList(getDS())).
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

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