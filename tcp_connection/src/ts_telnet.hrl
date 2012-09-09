
-record(pstate, {input=[],
		parsed="" ::string(),
		parsed_list=[] ::[string()],
		selection_list=[] ::[string()],
		str_list=[] ::[string()],
		completion=[] ::string(),
		number_list =[] ::[integer()],
		command=[] ::#command{} % holds the command record for later use
	       }).

-record(node, {
	  node_entry_fun ::function(),
	  commandListTableID =[] ::atom(),
	  nodeID =[] ::atom(),
	  exec_mode ::user | root,
	  configuration_level ::string(),
	  indention_level= 0 ::integer()
	 }).


