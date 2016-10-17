%%% Name: gossip_config.hrl
%%% Project: Gossip System
%%%	Author: Hang Gao
%%% Description: This is the file that defines macros and configuration of gossip protocol. It works similar to C. Feel free to add
%%%	your own made macros and configs.
-ifndef(gossip_config).
-define(gossip_config, gc).
%%%--- define timeout
%%% Input: timeout_const
%%% Output: 500 
%%% Example: ?timeout_const -> 500
-define(timeout_const, 500).

%%%--- define the punctuation list
-define(punctuation_const, [",",".",":","!","?",";","\"","<",">","(",")","[","]","{","}"]).

%%%-define(SEPERATOR, ":").
-define(SEPERATOR, "$").

%%%--- define a macro to calculate node address
%%% Input: NNAME: node name; NADDR: the machine name of the node
%%% Output: NNAME@NADDR 
%%% Example: ?addr(Dean, Godnode)
-define(addr(NNAME, NADDR), lists:concat([NNAME, "@", NADDR])).

%%% define all constants used
-define(NODE_NUMBER, "node_num").
-define(DATA_FILE, "data_file").
-define(HOME_DIREC, "home").
-define(NODES_ADDRESS, "nodes_address").

-define(NODE_CONFIG_FILE, "node_config_file").
-define(NODE_DATA_FILE, "node_data_file").
-define(NODE_ID, "node_id").
-define(NODE_HOME, "node_home").
-define(NODE_NEIGHBOR, "node_neighbor").
-define(NODE_NEIGHBOR_ID, "node_neighbor_id").
-define(NODE_NEIGHBOR_ADDR, "node_neighbor_addr").
-define(NODE_SEPERATOR, "%").
-define(NODE_MAX_RAND_FRAG, 3).
-define(NODE_FRAGLIST, "node_fraglist").

-define(NODE_EPOCH, "node_epoch").
-define(NODE_TEST_ITERATION, 10).

-define(DATA_MANAGER, dataManager).
-define(RECEIVER, receiverPrcName).
-define(SENDER, senderProcName).
-define(USERVER, userverProcName).
-define(EPOCH_MANAGER, epochmanager).

-endif.