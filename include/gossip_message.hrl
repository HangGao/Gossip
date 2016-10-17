%%% Name: gossip_message.hrl
%%% Project: Gossip System
%%%	Author: Hang Gao, Guohao Zhang
%%% Description: This is the file that defines the message interface. Any implementation of message should 
%%% inherit this interface file.
-ifndef(gossip_message).
-define(gossip_message, gm).

%%% ---- process identity in the global scheme ----
%%% identity: A unique ID hinting the type of the record. It's an identity of process
%%% responser_name: the name of the process
%%% responser_address: the address of the process node
-record(identity, {responser_name,responser_address}).


%%% ---- user query for aggregations ----
%%% mquery: A unique ID for the type of message. It stands for message query.
%%% qtype: the type of the query. It decides what kind of message are sending.
%%% sender: the nested record indicating the location of the sender process.
%%% message: content of the message
%%% Example: #mquery{qtype=LONGESTWORD, sender=#identity{responser_name=pong, responser_address=pong@godnode}, message="return the longest word"}
%%% There are several possible qtypes in this project:
%%%     longestWord: find the longest word in file F
%%%						message; not specified
%%%		whichNodes: find which nodes store the specified words
%%%						message; a list of query words
%%%		mostFreqWord: find the most frequent word in file F
%%%						message; not specified
%%%		updateFragment: update a fragment with specified fragment id and content.
%%%						message; {fragmentId, fragment words}
-record(mquery, {qtype, senderId=#identity{}, message}).

%%% --- epoch state ----
%%% epoch: A unique ID for the type of message. It stands for epoch state.
%%% epoch_id: the ID of current epoch.
%%% cycle_remain: the remaining cycle of current epoch
-record(epoch, {epoch_id, cycle_remain}).


%%% --- protocol communication ----
%%% pmessage: A unique ID for the type of message. It stands for protocol inner communication
%%% qtype: the type of the message. It decides what kind of aggregation in communication.
%%% sender: the nested record indicating the location of the sender process.
%%% epoch: a nested record of current epoch state
%%% message: content of the message
%%% There are several possible qtype in this project:
%%%     longestWord:  	the longest word in file F
%%%						message: A list that stores all longest words (All Capital)
%%%						senderId: local local receiver id if is sent to userver, 
%%%									the neighbour sender's id if sent to receiver

%%%		whichNodes:  which nodes store the specified words
%%%						message: The HitDict that stores the hit nodes
%%%						senderId: local local receiver id if is sent to userver, 
%%%									the neighbour sender's id if sent to receiver
%%%		mostFreqWord: the most frequent word in file F
%%%						message: The word list
%%%		epochKeepUp: need to kill current process and keep up with new epoch
%%%						message: The new epochState
%%%						senderId: the node that we need to keepUp with
-record(pmessage, {qtype, senderId=#identity{}, epoch=#epoch{}, message}).

%%% reply, don't need to reply again
-record(pRepmessage, {qtype, senderId=#identity{}, epoch=#epoch{}, message}).

-record(badepoch, {dead, epoch=#epoch{}}).

%%% --- broad cast query ---\
-record(broadcastQuery, {epoch=#epoch{}, queryContent=#mquery{}}).

%%% --- userver query ---
-record(userverQuery,{qtype, message}).

%%% --- query sent to receiver ---
-record(receiverResponse,{qtype, message}).

-record(result,{message}).

-endif.