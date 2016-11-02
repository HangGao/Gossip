# A Distributed System based on Gossip Algorithm
An implementation of a system for the following tasks: (1) Query and retrieve interested information across nodes distributed in a network, e.g., Find the longest word, Find the most frequent word, Find the location of words, etc.; (2) Update contents stored in fragments across the network.

# Requirements
[Erlang](https://www.erlang.org/) 

# Usage:
* Step 1: **Make initialization information for the entire system.** 
  Before starting any node of the gossip network, you need to first invoke `gossip_application: init("PATH_TO_CONFIG_FILE").` to generate all necessary data our system depends on. The correct running of the method relies on a config file, whose structure is given as follows, along with other necessary files:
 
 _Config File_
 ~~~
 node_num $   this is the total number of nodes in the gossip network
 data_file$   the absolute path of the data file which contains all text.
 home     $   the absolute path of home directory, under which all generated node info will be put.
 nodes_address$   the absolute path of the node address file which contains the addresses of all nodes
 ~~~
 
 _Data File_ (Example)
 ~~~
 In his notebooks, he would write a first draft of every letter, cataloging his thoughts from his days imprisoned on Robben Island and later in Pollsmoor Prison.
 ~~~
 
 _Node Address File_
 ~~~
 1$node_1@10.0.2.15  %% 1 is the ID of node and "node_1@10.0.2.15" is the address
 2$node_2@10.0.2.15  %% same as above
 ~~~
 
 _Node Config File_
 ~~~
 node_id$2
 node_home$C:/Users/GuohaoZhang/Eclipse/workspace/Proj/gossip_system/src/nodes/2
 node_neighbor$2%1%3
 2$node_2@127.0.0.1
 1$node_1@127.0.0.1
 3$node_3@127.0.0.1
 ~~~
 
 You should see ok message if successfully generated all information. If failed, please check your config file carefully and make any correction if necessary. You may also notice some files and folders under HOME directory are generated if success.
 
* Now you can start each node from the command line. Before that, please correct each node's config file if necessary. Invoke this method `gossip_node:run(CONFIG_FILE)` to start a node.You should see several success messages after doing that. We also provide a script written in bash to start multiple nodes simutaniously. It is proven to be useful in Linux system.

* Step 3: Now you can type in user query to any nodes. We provide the following user interface:
  
  Find the Longest Word
  ~~~
  gossip_user_interface:find_longest_word(NODE_ADDRESS).
  Example: gossip_user_interface:find_longest_word('node_1@127.0.0.1').
  ~~~
  
  Find the Location of Word(s)
  ~~~
  gossip_user_interface:which_nodes(NODE_ADDRESS, WORD_LIST).
  Example: gossip_user_interface:which_nodes('node_1@127.0.0.1', ["he","his"]).
  ~~~
  
  Find the Most Frequent Word
  ~~~
  gossip_user_interface:most_freq_word(NODE_ADDRESS).
  Example: gossip_user_interface:most_freq_word('node_1@127.0.0.1').
  ~~~
  
  Update Fragment
  ~~~
  gossip_user_interface:update_fragment(NODE_ADDRESS,FRAG_ID,FRAG_CONTENT).
  Example: gossip_user_interface:update_fragment('node_1@127.0.0.1',"2", ["good"]).
  ~~~
