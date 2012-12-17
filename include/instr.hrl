%%%----------------------------------------------------------------------
%%% Copyright (c) 2011, Alkis Gotovos <el3ctrologos@hotmail.com>,
%%%                     Maria Christakis <mchrista@softlab.ntua.gr>
%%%                 and Kostis Sagonas <kostis@cs.ntua.gr>.
%%% All rights reserved.
%%%
%%% This file is distributed under the Simplified BSD License.
%%% Details can be found in the LICENSE file.
%%%----------------------------------------------------------------------
%%% Authors     : Ilias Tsitsimpis <iliastsi@hotmail.com>
%%% Description : Instrumentation header file
%%%----------------------------------------------------------------------

%%%----------------------------------------------------------------------
%%% Definitions
%%%----------------------------------------------------------------------

%% Module containing replacement functions.
-define(REP_MOD, concuerror_rep).

%% Callback function mapping.
%% The callback functions should be in `?REP_MOD' module.
%% Each callback function should take as arguments:
%%   1: A tupple representing the module, function and arity
%%   2: A tupple representing the file and the source line
%%   3: A list with the arguments
%% For most of the cases rep_generic should be sufficient
-define(INSTR_MOD_FUN,
    %% Auto-imported functions of 'erlang' module.
    [{{erlang, demonitor, 1},           rep_demonitor},
     {{demonitor, 1},                   rep_demonitor},
     {{erlang, demonitor, 2},           rep_demonitor},
     {{demonitor, 2},                   rep_demonitor},
     {{erlang, halt, 0},                rep_halt},
     {{halt, 0},                        rep_halt},
     {{erlang, halt, 1},                rep_halt},
     {{halt, 1},                        rep_halt},
     {{erlang, is_process_alive, 1},    rep_is_process_alive},
     {{is_process_alive, 1},            rep_is_process_alive},
     {{erlang, link, 1},                rep_link},
     {{link, 1},                        rep_link},
     {{erlang, monitor, 2},             rep_monitor},
     {{monitor, 2},                     rep_monitor},
     {{erlang, process_flag, 2},        rep_process_flag},
     {{process_flag, 2},                rep_process_flag},
     {{erlang, register, 2},            rep_register},
     {{register, 2},                    rep_register},
     {{erlang, spawn, 1},               rep_spawn},
     {{spawn, 1},                       rep_spawn},
     {{erlang, spawn, 3},               rep_spawn},
     {{spawn, 3},                       rep_spawn},
     {{erlang, spawn_link, 1},          rep_spawn_link},
     {{spawn_link, 1},                  rep_spawn_link},
     {{erlang, spawn_link, 3},          rep_spawn_link},
     {{spawn_link, 3},                  rep_spawn_link},
     {{erlang, spawn_monitor, 1},       rep_spawn_monitor},
     {{spawn_monitor, 1},               rep_spawn_monitor},
     {{erlang, spawn_monitor, 3},       rep_spawn_monitor},
     {{spawn_monitor, 3},               rep_spawn_monitor},
     {{erlang, spawn_opt, 2},           rep_spawn_opt},
     {{spawn_opt, 2},                   rep_spawn_opt},
     {{erlang, spawn_opt, 4},           rep_spawn_opt},
     {{spawn_opt, 4},                   rep_spawn_opt},
     {{erlang, unlink, 1},              rep_unlink},
     {{unlink, 1},                      rep_unlink},
     {{erlang, unregister, 1},          rep_unregister},
     {{unregister, 1},                  rep_unregister},
     {{erlang, whereis, 1},             rep_whereis},
     {{whereis, 1},                     rep_whereis},
     {{erlang, send, 2},                rep_send},
     {{erlang, send, 3},                rep_send},
    %% Functions from ets module.
     {{ets, new, 2},                    rep_ets_new},
     {{ets, insert_new, 2},             rep_ets_insert_new},
     {{ets, lookup, 2},                 rep_ets_lookup},
     {{ets, select_delete, 2},          rep_ets_select_delete},
     {{ets, insert, 2},                 rep_ets_insert},
     {{ets, delete, 1},                 rep_ets_delete},
     {{ets, delete, 2},                 rep_ets_delete},
     {{ets, match_object, 1},           rep_ets_match_object},
     {{ets, match_object, 2},           rep_ets_match_object},
     {{ets, match_object, 3},           rep_ets_match_object},
     {{ets, foldl, 3},                  rep_ets_foldl},
     {{ets, info, 1},                   rep_ets_info},
     {{ets, info, 2},                   rep_ets_info}
    ]).
