%%% Name: gossip_application.erl
%%% Project: Gossip System
%%%	Author: Hang Gao
%%% Description: This is the application file where all the work of initialization stage should be finished

-module(gossip_application).

%% ====================================================================
%% API functions
%% ====================================================================
-export([init/1]).
-include("gossip_config.hrl").
-include("gossip_message.hrl").

%%%---init-----
%%% Description: It is the function to perform all initialization tasks
%%% Requirement: 
%%%			1. Read config file, get all configuration data, including node number, file location and home directory
%%%			2. Read the data file, get all words
%%%			3. Split the word list according to the number of words, assign each fragment with a fragment ID
%%%			4. Generate config info for each node, including the node name, process name, number of fragment assigned, 
%%%			   fragment IDs and fragment filenames, number of neighbors, neighbor IDs.
%%%			5. Create node home directory for each node
%%%			6. Write all config info along with fragments to the home directory of each node in split files.
init(Config_file) ->
	
	% start step 1
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
					% get node number
					case dict:find(?NODE_NUMBER, Configure) of
						{ok, [Value|Rest]} ->
							% parse string to int
							case gossip_libtool:string_to_int(Value) of
								{error, Reason} ->
									erlang:exit({error, Reason});
								{ok, Val} ->
									erlang:put(?NODE_NUMBER, Val)
							end;
						error ->
							erlang:exit({error, "Error: missing node number"})
					end,
					% get data file
					case dict:find(?DATA_FILE, Configure) of
						{ok, []} ->
							erlang:exit({error, "Error: missing data file"});
						{ok, [Data_file|_]} ->
							erlang:put(?DATA_FILE, Data_file);
						error ->
							erlang:exit({error, "Error: missing data file"})
					end,
					% get home dir
					case dict:find(?HOME_DIREC, Configure) of
						{ok, [Home|_]} ->
							erlang:put(?HOME_DIREC, Home);
						error ->
							erlang:exit({error, "Error: missing home directory"})
					end,
					% get node addresses
					case dict:find(?NODES_ADDRESS, Configure) of
						{ok, [Nodes_address|_]} ->
							erlang:put(?NODES_ADDRESS, Nodes_address);
						error ->
							erlang:exit({error, "Error: missing node addresses"})
					end,
					% start step 2
					case erlang:get(?DATA_FILE) of
						undefined ->
							erlang:exit({error, "Error: cannot find data file"});
						Dfile ->
							case gossip_io:read_file_by_line(Dfile) of
								{error, Reason_2} ->
									erlang:exit({error, Reason_2});
								Raw_data ->
									Data = parse_data(lists:append(Raw_data)),
									% start step 3
									case erlang:get(?NODE_NUMBER) of
										undefined ->
											erlang:exit({error, "Error: cannot find node number"});
										Node_number ->
											Frag_size =  gossip_libtool:int_ceil(gossip_libtool:list_size(Data)/Node_number),
											Frag_list = gossip_libtool:index_list(gossip_libtool:split_list(Data, Frag_size)),
											Node_ids = gossip_libtool:range(Node_number),
											case get_all_addresses(erlang:get(?NODES_ADDRESS)) of
												{error, _} ->
													erlang:exit({error, "Error: cannot read node address file"});
												{ok, Address_dict}->
													lists:foreach(
													  fun(X)->
															erlang:put(X, [])
													  end , Node_ids),
													random_neighbors(Node_ids),
													lists:foreach(fun(X)-> node(X, Node_ids, Frag_list, Address_dict) end, Node_ids)	
											end
									end
							end
					end
			end
	end.

%% read all configure into dictionary
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

parse_data(Raw_data) ->
	Word_list = string:tokens(Raw_data, string:join([" "|?punctuation_const], "")),
	lists:map(fun(X)->string:to_lower(X) end, Word_list).

node(ID, ID_list, Frag_list, Address_dict) ->
	% create home dir for the node
	Home = string:join([erlang:get(?HOME_DIREC), erlang:integer_to_list(ID)], "/"),
	Config_file = string:join([Home, ?NODE_CONFIG_FILE], "/"),
	filelib:ensure_dir(Config_file),
	case file:open(Config_file, [write, raw]) of
		{ok, F_handler} ->
				Node_attr_1 = string:concat(string:join([?NODE_ID, erlang:integer_to_list(ID)], ?SEPERATOR), "\n"),
				file:write(F_handler, Node_attr_1),
				Node_attr_2 = string:concat(string:join([?NODE_HOME, Home], ?SEPERATOR), "\n"),
				file:write(F_handler, Node_attr_2),
				Node_attr_3 = lists:map(
								fun(X) ->erlang:integer_to_list(X) end,  
						 		erlang:get(ID)),
				file:write(F_handler, string:concat(string:join([?NODE_NEIGHBOR, 
																 string:join(Node_attr_3, ?NODE_SEPERATOR)], 
																?SEPERATOR), "\n")),
				lists:foreach(
				  fun(X) ->
						  case dict:find(X, Address_dict) of
							  error ->
								  erlang:exit({error, string:concat("Error: cannot find the address of a node: ", X)});
							  {ok, Val} ->
								  file:write(F_handler, string:concat(string:join([X,Val], ?SEPERATOR), "\n"))
						  end
				  end
						  , Node_attr_3),
				Node_attr_4 = random_frag_list(ID, Frag_list),
				file:close(F_handler),
				Data_file = string:join([Home, ?NODE_DATA_FILE], "/"),
				filelib:ensure_dir(Data_file),
				case file:open(Data_file, [write, raw]) of
					{error, Reason_3} ->
			 				erlang:exit({error, Reason_3});
					{ok, F_handler2} ->
							lists:foreach(
							  fun(X)->
									  write_one_fragment(X, F_handler2) 
							  end
								   ,Node_attr_4),
							file:close(F_handler2)
				end;
		{error, Reason_2} ->
				erlang:exit({error, Reason_2})
	end.

write_one_fragment([ID, Content], F_handler) ->
	file:write(F_handler, string:concat(erlang:integer_to_list(ID), "\n")),
	file:write(F_handler, string:concat(string:join(Content, " "),"\n")).

neighbor_in_chain(_, []) ->
	none;
neighbor_in_chain(ID, [Head|Tail]) ->
	case ID == lists:nth(gossip_libtool:list_size([Head|Tail]), [Head|Tail]) of
		true ->
			case ID == Head of
				true ->
					none;
				false ->
					Head
			end;
		false ->
			next_member(ID, [Head|Tail])
	end.

next_member(_, []) ->
	none;
next_member(_, [_]) ->
	none;
next_member(ID, [First, Second|Tail]) ->
	case ID == First of
		true ->
			Second;
		false ->
			next_member(ID, [Second|Tail])
	end.

random_neighbor_list(ID, ID_list) ->
	Neighbor = neighbor_in_chain(ID, ID_list),
	Size = gossip_libtool:list_size(ID_list),
	Rand_neighbor_num = random:uniform(Size)-1,
	RS = [Neighbor],
	get_random_list(ID, ID_list, Size, Rand_neighbor_num, RS).

random_neighbors(ID_list) ->
	Size = gossip_libtool:list_size(ID_list),
	lists:foreach(
	  fun(X) ->
			  Neighbor = neighbor_in_chain(X, ID_list),
			  erlang:put(X, erlang:get(X) ++ [Neighbor]),
			  erlang:put(Neighbor, erlang:get(Neighbor)++[X])
	  end
		   , ID_list),
	  Rand_neighbor_num = random:uniform(Size * Size),
	  lists:foreach(
	  				fun(_) ->
						A = lists:nth(random:uniform(Size), ID_list),
						B = lists:nth(random:uniform(Size), ID_list),
						case A /= B of
							true ->
								case gossip_libtool:list_contain(B, erlang:get(A)) of
									true ->
										done;
									false ->
										case gossip_libtool:list_contain(A, erlang:get(B)) of
											true ->
												done;
											false ->
												erlang:put(A, erlang:get(A)++[B]),
			 									erlang:put(B, erlang:get(B)++[A])
										end
								end;
							false ->
								done
						end	 
					end,
						gossip_libtool:range(Rand_neighbor_num)).


get_random_list(Idx, List, Size, Random_num, RS) ->
	case Random_num == 0 of
		true ->
			RS;
		false ->
			RID = lists:nth(random:uniform(Size), List),
			case gossip_libtool:list_contain(RID, RS) of
				true ->
					get_random_list(Idx, List, Size, Random_num-1, RS);
				false ->
					case Idx == RID of
						false ->
							New_list = [RID|RS],
							get_random_list(Idx, List, Size, Random_num-1, New_list);
						true ->
							get_random_list(Idx, List, Size, Random_num-1, RS)
					end
			end	
	end.

random_frag_list(ID, Frag_list) ->
	Size = gossip_libtool:list_size(Frag_list),
	Rand_num = random:uniform(gossip_libtool:int_ceil(math:sqrt(Size)))-1,
	case ID =< Size of
		true ->
			RS = [lists:nth(ID, Frag_list)],
			get_random_list(ID, Frag_list, Size, Rand_num, RS);
		false ->
			Idx = ID rem Size,
			case Idx == 0 of
				true ->
					RS = [lists:nth(Idx+1, Frag_list)],
					get_random_list(Idx+1, Frag_list, Size, Rand_num, RS);
				false ->
					RS = [lists:nth(Idx, Frag_list)],
					get_random_list(Idx, Frag_list, Size, Rand_num, RS)
			end
	end.

get_all_addresses(Address_file) ->
	Lines = gossip_io:read_file_by_line(Address_file),
	case Lines of
		{error, Reason} ->
			{error, Reason};
		_ ->
			read_all_configs(dict:new(), Lines)
	end.
	

%% ====================================================================
%% Internal functions
%% ====================================================================


