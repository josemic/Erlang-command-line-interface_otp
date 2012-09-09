{application, tcp_server,
[{description, "A simple TCP server"},
{vsn, "0.1.0"},
{modules, [
	tcp_connection, 
	tcp_connector, 
	ts_root_sup,
	tcp_connection_sup,
	ts_app 
	]},
{registered,[ts_root_sup]},
{applications, [kernel]},
{mod, {ts_app,[]}}
]}.         
