-module(gossip_io).

%% ====================================================================
%% API functions
%% ====================================================================
-export([read_file_by_line/1, write_file_by_line/2]).
-include("gossip_config.hrl").
-include("gossip_message.hrl").

%%% ----- read_text_file -----
%%% Description: read a text file given its path and return analyzed content in the given store list.
%%% Requirement: 
%%%			1. open and close file
%%%			2. words separated by space with punctuation eliminated(punctuation are defined in config file)
%%% Exception Handling:
%%%			1. File not found
%%%			2. sList not empty
read_file_by_line(F_path) ->
	case file:open(F_path, [raw, read, read_ahead]) of
		{error, Reason} ->
			{error, Reason};
		{ok, F_handler} ->
			read_lines(F_handler,[])
	end.

read_lines(F_handler, Lines) ->
	case file:read_line(F_handler) of
		{ok, Data} -> 
			read_lines(F_handler, [string:strip(Data, both, $\n)|Lines]);
		eof -> 
			lists:reverse(Lines);
		{error, Reason} -> 
			{error, Reason}
	end.
	
%%% ---- write_text_file -----
%%% Description: write a list of words to the file given its path
%%% Requirement:
%%%			1. open and close file
%%%			2. use space between words
write_file_by_line(Fpath, Lines) ->
	done.

