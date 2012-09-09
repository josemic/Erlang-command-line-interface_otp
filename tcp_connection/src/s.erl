
-module(s).
-export([s/0]).

s() ->
    application:start(sasl),
    application:set_env(tcp_server, port, 1026),
    application:set_env(tcp_server, conf_file, "ConfigurationUnix"),
    application:start(tcp_server),
    appmon:start(),
    appl1:start().
