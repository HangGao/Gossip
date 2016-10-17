%%% Name: gossip_libtool.erl
%%% Project: Gossip System
%%%	Author: Lianjie Sun
%%% Description: This is the file where you should define all tool functions.

-module(gossip_libtool).

%% ====================================================================
%% API functions
%% ====================================================================
-export([list_size/1, string_to_int/1, split_list/2, range/1, list_contain/2, index_list/1, int_ceil/1
		, findLongestWords/1, removeDuplicateFromList/1, safeSendMsg/2, mergeDict/2, mergeFreqDict/2, convertToList/1, findValueInList/2,
		 findMostFrequent/1, hasWord/2, getWordFrequency/1,replaceNth/3]).
%%% --- function to count the number of elements in the list
list_size([]) ->
	0;
list_size([Head|Tail]) ->
	1+list_size(Tail).

%%% --- function to split a list, define it by yourself.


string_to_int(String) ->
	case string:to_integer(String) of
		{error, Reason} ->
				{error, Reason};
		{Int, Rest} ->
				{ok, Int}
	end.


split_list(List, Size) ->
	case Size < list_size(List) of
		true ->
			{L1, L2} = lists:split(Size, List),
			[L1]++split_list(L2,Size);
		false ->
			[List]
	end.

index_list_(Idx, []) ->
	[];
index_list_(Idx, [Head|Tail]) ->
	[[Idx, Head]|index_list_(Idx+1, Tail)].

index_list([]) ->
	[];
index_list([Head|Tail]) ->
	index_list_(1, [Head|Tail]).

% creat a list containing 1, 2, ..., N
range(I, N)->
	case I =< N of
		true ->
			[I|range(I+1,N)];
		false ->
			[]
	end.

range(N) ->
	range(1, N).


list_contain(Ele, []) ->
	false;
list_contain(Ele, [E|Rest]) ->
	case Ele == E of
		true ->
			true;
		false ->
			list_contain(Ele, Rest)
	end.

int_ceil(X) ->
	T = trunc(X),
	case (X-T) of
		Neg when Neg < 0 -> T;
		Pos when Pos > 0 -> T+1;
		_ -> T
	end.
%% ====================================================================
%% Internal functions
%% ====================================================================


%% find arbitry word that has longest length
findOneLongestWord(WordList) ->
	lists:foldl(fun(X,Y) when length(X) > length(Y) ->
                X;
               (_, Acc) ->
                 Acc
            end, ["",""], WordList).

%% find the word list that has the same length as LongestWord
getSameLength(WordList, LongestWord) ->
	lists:foldl(fun(X, List) when length(X) == length(LongestWord) ->
                lists:append(List,[X]);
               (_,Acc) ->
                 Acc
            end, [], WordList).

%% as name indicates
removeDuplicateFromList(List) ->
	lists:usort(List).

%% combine the last two
findLongestWords(WordList) ->
	LongestWord = findOneLongestWord(WordList),
	removeDuplicateFromList(getSameLength(WordList, LongestWord)).

%% only send msg if the Sender is defined
safeSendMsg(Sender, Msg) ->
	case whereis(Sender) of
		undefined ->
			done;
		_ ->
			Sender ! Msg
	end.

%% description: find word in a list
%% return 
%% true if found
%% flase if not found
searchWord(Word, []) ->
    false;

searchWord ( Word, [ Item | ListTail ] ) ->
    case ( Item == Word ) of
        true    ->  true;
        false   ->  searchWord(Word, ListTail)
    end.

%% description calculate the word frequency of words in the list
%% return a dictionary with words and frequencies.
getWordFrequency(List) ->
	lists:foldl(fun(Word,Dict) -> 
					case dict:is_key( Word, Dict ) of
					true ->
    					dict:store( Word, dict:fetch( Word, Dict ) + 1, Dict );
					false ->
    					dict:store( Word, 1, Dict )
					end;
				(_, Acc) ->
                 Acc
				end, dict:new(), List).

%% description check if a word form a list is in current node
%% if yes, add current node to word's nodes_list
%% input: List of query words, List of words in current node 
%% return: dict(word, nodes_list)

hasWord(QueryWordList, CurrentWordList) ->
	NoDuplicateWordList = removeDuplicateFromList(CurrentWordList),
	lists:foldl(fun(Word,Dict) ->
						case searchWord(Word,NoDuplicateWordList) of
							true ->
								dict:store(Word, [node()], Dict);
							false ->
								dict:store(Word, [], Dict)
						end;
				(_, Acc) ->
                 Acc
				end, dict:new(), QueryWordList).

%% description merge the current node word dict and passed word dict
%% return a merged dict with no duplicate

mergeDict(CurrentDict, PassedDict) ->
	Words = dict:fetch_keys(CurrentDict),
	lists:foldl(fun(Word, MergedDict) ->
						dict:store(Word, 
								   removeDuplicateFromList(lists:append(dict:fetch(Word, CurrentDict), dict:fetch(Word, PassedDict))), 
								   MergedDict);
				(_, Acc) ->
                 Acc
            	end, dict:new(), Words).

%% description merge current node frequency dict and passed
%% return merged dict (Word, Frequency)
mergeFreqDict(CurrentDict, PassDict) ->
	Words = dict:fetch_keys(CurrentDict),
	lists:foldl(fun(Word, MergedDict) ->
					case dict:is_key(Word, PassDict) of 
						true -> 
							dict:store(Word, (dict:fetch(Word, CurrentDict) + dict:fetch(Word, PassDict))/2, MergedDict);
						false ->
							dict:store(Word, dict:fetch(Word, CurrentDict)/2, MergedDict)
					end;
				(_, Acc) ->
                 Acc
            	end	, dict:new(), Words).

%% description find the most frequent word in the dictionary
%% return a tupe which contain the most frequent word
findMostFrequent(Dictionary) ->
	Words = dict:fetch_keys(Dictionary),
	Frequency = lists:foldl(fun(Word, MostFrequent) ->
					 case(dict:fetch(Word, Dictionary) > MostFrequent) of
						true ->
						 dict:fetch(Word, Dictionary);
					 	false ->
						 MostFrequent
					 end;
				(_, Acc) ->
                 Acc
            end, 0, Words),
	
	WordWithThisFre = lists:foldl(fun(Word, FrequentWord) ->
							case(dict:fetch(Word, Dictionary) == Frequency) of
								true ->
									Word;
								false ->
									FrequentWord
							end;
					(_, Acc) ->
                 Acc
            end, "", Words),
	
	{WordWithThisFre,Frequency}.

%% decription convert list_list to list
%% return the converted list
convertToList(Listlist) ->
	lists:foldl(fun(List,ConvertedList) ->
						lists:append(List,ConvertedList)
						end, [], Listlist).

%%% replace nth element in the list
replaceNth(N, List, Ele) ->
	lists:sublist(List,N-1) ++ [Ele] ++ lists:nthtail(N,List).

%% check if the value is in the fragment list
%% return the index of the value
%% return 0 if not found
findValueInList(List, Value) ->
	string:str(List, [Value]).