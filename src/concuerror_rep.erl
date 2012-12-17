%%%----------------------------------------------------------------------
%%% Copyright (c) 2011, Alkis Gotovos <el3ctrologos@hotmail.com>,
%%%                     Maria Christakis <mchrista@softlab.ntua.gr>
%%%                 and Kostis Sagonas <kostis@cs.ntua.gr>.
%%% All rights reserved.
%%%
%%% This file is distributed under the Simplified BSD License.
%%% Details can be found in the LICENSE file.
%%%----------------------------------------------------------------------
%%% Authors     : Alkis Gotovos <el3ctrologos@hotmail.com>
%%%               Maria Christakis <mchrista@softlab.ntua.gr>
%%% Description : Replacement BIFs
%%%----------------------------------------------------------------------

-module(concuerror_rep).

-export([spawn_fun_wrapper/1, rep_var/4]).

-export([rep_send/3]).

-export([rep_spawn/3, rep_spawn_link/3,
         rep_spawn_monitor/3, rep_spawn_opt/3]).

-export([rep_link/3, rep_unlink/3, rep_process_flag/3]).

-export([rep_receive/3, rep_receive_block/1,
         rep_after_notify/1, rep_receive_notify/4,
         rep_receive_notify/2]).

-export([rep_ets_insert_new/3, rep_ets_lookup/3, rep_ets_select_delete/3,
         rep_ets_insert/3, rep_ets_delete/3,
         rep_ets_match_object/3, rep_ets_info/3,
         rep_ets_match_delete/3, rep_ets_new/3, rep_ets_foldl/3]).

-export([rep_register/3, rep_is_process_alive/3,
         rep_unregister/3, rep_whereis/3]).

-export([rep_monitor/3, rep_demonitor/3]).

-export([rep_halt/3]).

-include("gen.hrl").
-include("instr.hrl").

%%%----------------------------------------------------------------------
%%% Definitions and Types
%%%----------------------------------------------------------------------

%% Return the calling process' LID.
-define(LID_FROM_PID(Pid), concuerror_lid:from_pid(Pid)).

%%%----------------------------------------------------------------------
%%% Callbacks
%%%----------------------------------------------------------------------

%% Handle Mod:Fun(Args) calls.
-spec rep_var(term(), module(), atom(), [term()]) -> term().
rep_var(PosArg, Mod, Fun, Args) ->
    Key = {Mod, Fun, length(Args)},
    case lists:keyfind(Key, 1, ?INSTR_MOD_FUN) of
        {Key, RepFun} -> apply(?REP_MOD, RepFun, [Key, PosArg, Args]);
        false -> apply(Mod, Fun, Args)
    end.

%% ---------------------------
rep_demonitor(_Key, _PosArg, [Ref]) ->
    concuerror_sched:notify(demonitor, concuerror_lid:lookup_ref_lid(Ref)),
    demonitor(Ref);
rep_demonitor(_Key, _PosArg, [Ref, Opts]) ->
    concuerror_sched:notify(demonitor, concuerror_lid:lookup_ref_lid(Ref)),
    case lists:member(flush, Opts) of
        true ->
            receive
                {?INSTR_MSG, _, _, {_, Ref, _, _, _}} ->
                    true
            after 0 ->
                    true
            end;
        false ->
            true
    end,
    demonitor(Ref, Opts).

%% ---------------------------
rep_halt(_Key, _PosArg, []) ->
    concuerror_sched:notify(halt, empty);
rep_halt(_Key, _PosArg, [Status]) ->
    concuerror_sched:notify(halt, Status).

%% ---------------------------
rep_is_process_alive(_Key, _PosArg, [Pid]) ->
    case ?LID_FROM_PID(Pid) of
        not_found -> ok;
        PLid -> concuerror_sched:notify(is_process_alive, PLid)
    end,
    is_process_alive(Pid).

%% ---------------------------
rep_link(_Key, _PosArg, [Pid]) ->
    case ?LID_FROM_PID(Pid) of
        not_found -> ok;
        PLid -> concuerror_sched:notify(link, PLid)
    end,
    link(Pid).

%% ---------------------------
rep_monitor(_Key, _PosArg, [Type, Item]) ->
    case ?LID_FROM_PID(find_pid(Item)) of
        not_found -> monitor(Type, Item);
        Lid ->
            concuerror_sched:notify(monitor, {Lid, unknown}),
            Ref = monitor(Type, Item),
            concuerror_sched:notify(monitor, {Lid, Ref}, prev),
            concuerror_sched:wait(),
            Ref
    end.

%% ---------------------------
rep_process_flag(_Key, _PosArg, [trap_exit = Flag, Value]) ->
    {trap_exit, OldValue} = process_info(self(), trap_exit),
    case Value =:= OldValue of
        true -> ok;
        false ->
            PlannedLinks = find_my_links(),
            concuerror_sched:notify(process_flag, {Flag, Value, PlannedLinks}),
            Links = find_my_links(),
            concuerror_sched:notify(process_flag, {Flag, Value, Links}, prev)
    end,
    process_flag(Flag, Value);
rep_process_flag(_Key, _PosArg, [Flag, Value]) ->
    process_flag(Flag, Value).

find_my_links() ->
    {links, AllPids} = process_info(self(), links),
    AllLids = [?LID_FROM_PID(Pid) || Pid <- AllPids],
    [KnownLid || KnownLid <- AllLids, KnownLid =/= not_found].                  

%% ---------------------------
rep_receive(_PosArg, Fun, HasTimeout) ->
    case ?LID_FROM_PID(self()) of
        not_found ->
            %% XXX: Uninstrumented process enters instrumented receive
            ok; 
        _Lid ->
            rep_receive_loop(poll, Fun, HasTimeout)
    end.

rep_receive_loop(Act, Fun, HasTimeout) ->
    case Act of
        Resume when Resume =:= ok;
                    Resume =:= continue -> ok;
        poll ->
            {messages, Mailbox} = process_info(self(), messages),
            case rep_receive_match(Fun, Mailbox) of
                block ->
                    NewAct =
                        case HasTimeout of
                            infinity -> concuerror_sched:notify('receive', blocked);
                            _ ->
                                NewFun =
                                    fun(Msg) ->
                                        case rep_receive_match(Fun, [Msg]) of
                                            block -> false;
                                            continue -> true
                                        end
                                    end,
                                concuerror_sched:notify('after', NewFun)
                        end,
                    rep_receive_loop(NewAct, Fun, HasTimeout);
                continue ->
                    Tag =
                        case HasTimeout of
                            infinity -> unblocked;
                            _ -> had_after
                        end,
                    continue = concuerror_sched:notify('receive', Tag),
                    ok
            end
    end.

rep_receive_match(_Fun, []) ->
    block;
rep_receive_match(Fun, [H|T]) ->
    case Fun(H) of
        block -> rep_receive_match(Fun, T);
        continue -> continue
    end.

%% ---------------------------
%% Blocks forever (used for 'receive after infinity -> ...' expressions).
rep_receive_block(PosArg) ->
    Fun = fun(_Message) -> block end,
    rep_receive(PosArg, Fun, infinity).

%% ---------------------------
rep_after_notify(_PosArg) ->
    ok.

%% ---------------------------
rep_receive_notify(_PosArg, From, CV, Msg) ->
    concuerror_sched:notify('receive', {From, CV, Msg}, prev),
    ok.

%% ---------------------------
rep_receive_notify(_PosArg, _Msg) ->
    %% XXX: Received uninstrumented message
    ok.

%% ---------------------------
rep_register(_Key, _PosArg, [RegName, P]) ->
    case ?LID_FROM_PID(P) of
        not_found -> ok;
        PLid ->
            concuerror_sched:notify(register, {RegName, PLid})
    end,
    register(RegName, P).

%% ---------------------------
rep_send(_Key, _PosArg, [Dest, Msg]) ->
    case ?LID_FROM_PID(self()) of
        not_found ->
            %% Unknown process sends using instrumented code. Allow it.
            %% It will be reported at the receive point.
            Dest ! Msg;
        _SelfLid ->
            PlanLid = ?LID_FROM_PID(find_pid(Dest)),
            concuerror_sched:notify(send, {Dest, PlanLid, Msg}),
            SendLid = ?LID_FROM_PID(find_pid(Dest)),
            concuerror_sched:notify(send, {Dest, SendLid, Msg}, prev),
            Dest ! Msg
    end;
rep_send(_Key, _PosArg, [Dest, Msg, Opt]) ->
    case ?LID_FROM_PID(self()) of
        not_found ->
            %% Unknown process sends using instrumented code. Allow it.
            %% It will be reported at the receive point.
            erlang:send(Dest, Msg, Opt);
        _SelfLid ->
            PlanLid = ?LID_FROM_PID(find_pid(Dest)),
            concuerror_sched:notify(send, {Dest, PlanLid, Msg}),
            SendLid = ?LID_FROM_PID(find_pid(Dest)),
            concuerror_sched:notify(send, {Dest, SendLid, Msg}, prev),
            erlang:send(Dest, Msg, Opt)
    end.

%% ---------------------------
rep_spawn(_Key, _PosArg, [Fun]) ->
    spawn_center(spawn, Fun);
rep_spawn(Key, PosArg, [Module, Function, Args]) ->
    Fun = fun() -> apply(Module, Function, Args) end,
    rep_spawn(Key, PosArg, [Fun]).

spawn_center(Kind, Fun) ->
    Spawner =
        case Kind of
            spawn -> fun spawn/1;
            spawn_link -> fun spawn_link/1;
            spawn_monitor -> fun spawn_monitor/1
        end,
    case ?LID_FROM_PID(self()) of
        not_found -> Spawner(Fun);
        _Lid ->
            concuerror_sched:notify(Kind, unknown),
            Result = Spawner(fun() -> spawn_fun_wrapper(Fun) end),
            concuerror_sched:notify(Kind, Result, prev),
            %% Wait before using the PID to be sure that an LID is assigned
            concuerror_sched:wait(),
            Result
    end.

-spec spawn_fun_wrapper(function()) -> term().
spawn_fun_wrapper(Fun) ->
    try
        concuerror_sched:wait(),
        Fun(),
        exit(normal)
    catch
        exit:normal ->
            MyInfo = find_my_info(),
            concuerror_sched:notify(exit, {normal, MyInfo}),
            MyRealInfo = find_my_info(),
            concuerror_sched:notify(exit, {normal, MyRealInfo}, prev);
        Class:Type ->
            concuerror_sched:notify(error,[Class,Type,erlang:get_stacktrace()]),
            case Class of
                error -> error(Type);
                throw -> throw(Type);
                exit  -> exit(Type)
            end
    end.                    

find_my_info() ->
    MyEts = find_my_ets_tables(),
    MyName = find_my_registered_name(),
    MyLinks = find_my_links(),
    {MyEts, MyName, MyLinks}.

find_my_ets_tables() ->
    Self = self(),
    MyTIDs = [TID || TID <- ets:all(), Self =:= ets:info(TID, owner)],
    Fold =
        fun(TID, {HeirsAcc, TablesAcc}) ->
            Survives =
                case ets:info(TID, heir) of
                    none -> false;
                    Self -> false;
                    Pid ->
                        case is_process_alive(Pid) of
                            false -> false;
                            true ->
                                case ?LID_FROM_PID(Pid) of
                                    not_found -> false;
                                    HeirLid0 -> {true, HeirLid0}
                                end
                        end
                end,
            case Survives of
                false ->
                    T =
                        {?LID_FROM_PID(TID),
                         case ets:info(TID, named_table) of
                             true -> {ok, ets:info(TID, name)};
                             false -> none
                         end},
                    {HeirsAcc, [T|TablesAcc]};
                {true, HeirLid} ->
                    {[HeirLid|HeirsAcc], TablesAcc}
            end
        end,
    lists:foldl(Fold, {[], []}, MyTIDs).

find_my_registered_name() ->
    case process_info(self(), registered_name) of
        [] -> none;
        {registered_name, Name} -> {ok, Name}
    end.

%% ---------------------------
rep_spawn_link(_Key, _PosArg, [Fun]) ->
    spawn_center(spawn_link, Fun);
rep_spawn_link(Key, PosArg, [Module, Function, Args]) ->
    Fun = fun() -> apply(Module, Function, Args) end,
    rep_spawn_link(Key, PosArg, [Fun]).

%% ---------------------------
rep_spawn_monitor(_Key, _PosArg, [Fun]) ->
    spawn_center(spawn_monitor, Fun);
rep_spawn_monitor(Key, PosArg, [Module, Function, Args]) ->
    Fun = fun() -> apply(Module, Function, Args) end,
    rep_spawn_monitor(Key, PosArg, [Fun]).

%% ---------------------------
rep_spawn_opt(_Key, _PosArg, [Fun, Opt]) ->
    case ?LID_FROM_PID(self()) of
        not_found -> spawn_opt(Fun, Opt);
        _Lid ->
            concuerror_sched:notify(spawn_opt, unknown),
            Result = spawn_opt(fun() -> spawn_fun_wrapper(Fun) end, Opt),
            concuerror_sched:notify(spawn_opt, Result, prev),
            %% Wait before using the PID to be sure that an LID is assigned
            concuerror_sched:wait(),
            Result
    end;
rep_spawn_opt(Key, PosArg, [Module, Function, Args, Opt]) ->
    Fun = fun() -> apply(Module, Function, Args) end,
    rep_spawn_opt(Key, PosArg, [Fun, Opt]).

%% ---------------------------
rep_unlink(_Key, _PosArg, [Pid]) ->
    case ?LID_FROM_PID(Pid) of
        not_found -> ok;
        PLid -> concuerror_sched:notify(unlink, PLid)
    end,
    unlink(Pid).

%% ---------------------------
rep_unregister(_Key, _PosArg, [RegName]) ->
    concuerror_sched:notify(unregister, RegName),
    unregister(RegName).

%% ---------------------------
rep_whereis(_Key, _PosArg, [RegName]) ->
    concuerror_sched:notify(whereis, {RegName, unknown}),
    R = whereis(RegName),
    Value =
        case R =:= undefined of
            true -> not_found;
            false -> ?LID_FROM_PID(R)
        end,
    concuerror_sched:notify(whereis, {RegName, Value}, prev),
    R.

%%%----------------------------------------------------------------------
%%% ETS replacements
%%%----------------------------------------------------------------------

%% ---------------------------
rep_ets_new(_Key, _PosArg, [Name, Options]) ->
    concuerror_sched:notify(ets, {new, [unknown, Name, Options]}),
    try
        Tid = ets:new(Name, Options),
        concuerror_sched:notify(ets, {new, [Tid, Name, Options]}, prev),
        concuerror_sched:wait(),
        Tid
    catch
        _:_ ->
	        %% Report a fake tid...
            concuerror_sched:notify(ets, {new, [-1, Name, Options]}, prev),
            concuerror_sched:wait(),
            %% And throw the error again...
            ets:new(Name, Options)
    end.

%% ---------------------------
rep_ets_insert(_Key, _PosArg, [Tab, Obj]) ->
    ets_insert_center(insert, Tab, Obj).

%% ---------------------------
rep_ets_insert_new(_Key, _PosArg, [Tab, Obj]) ->
    ets_insert_center(insert_new, Tab, Obj).

ets_insert_center(Type, Tab, Obj) ->
    KeyPos = ets:info(Tab, keypos),
    Lid = ?LID_FROM_PID(Tab),
    ConvObj =
        case is_tuple(Obj) of
            true -> [Obj];
            false -> Obj
        end,
    Keys = ordsets:from_list([element(KeyPos, O) || O <- ConvObj]),
    concuerror_sched:notify(ets, {Type, [Lid, Tab, Keys, KeyPos, ConvObj, true]}),
    case Type of
        insert -> ets:insert(Tab, Obj);
        insert_new ->
            Ret = ets:insert_new(Tab, Obj),
            Info = {Type, [Lid, Tab, Keys, KeyPos, ConvObj, Ret]},
            concuerror_sched:notify(ets, Info, prev),
            Ret
    end.

%% ---------------------------
rep_ets_lookup(_Key, _PosArg, [Tab, Key]) ->
    Lid = ?LID_FROM_PID(Tab),
    concuerror_sched:notify(ets, {lookup, [Lid, Tab, Key]}),
    ets:lookup(Tab, Key).

%% ---------------------------
rep_ets_delete(_Key, _PosArg, [Tab]) ->
    concuerror_sched:notify(ets, {delete, [?LID_FROM_PID(Tab), Tab]}),
    ets:delete(Tab);
rep_ets_delete(_Key, _PosArg, [Tab, Key]) ->
    concuerror_sched:notify(ets, {delete, [?LID_FROM_PID(Tab), Tab, Key]}),
    ets:delete(Tab, Key).

%% ---------------------------
rep_ets_select_delete(_Key, _PosArg, [Tab, MatchSpec]) ->
    concuerror_sched:notify(ets,
        {select_delete, [?LID_FROM_PID(Tab), Tab, MatchSpec]}),
    ets:select_delete(Tab, MatchSpec).

%% ---------------------------
rep_ets_match_delete(_Key, _PosArg, [Tab, Pattern]) ->
    concuerror_sched:notify(ets,
        {match_delete, [?LID_FROM_PID(Tab), Tab, Pattern]}),
    ets:match_delete(Tab, Pattern).

%% ---------------------------
rep_ets_match_object(_Key, _PosArg, [Continuation]) ->
    %% XXX: this is so wrong
    concuerror_sched:notify(ets,
        {match_object, [?LID_FROM_PID(self()), Continuation]}),
    ets:match_object(Continuation);
rep_ets_match_object(_Key, _PosArg, [Tab, Pattern]) ->
    concuerror_sched:notify(ets,
        {match_object, [?LID_FROM_PID(Tab), Tab, Pattern]}),
    ets:match_object(Tab, Pattern);
rep_ets_match_object(_Key, _PosArg, [Tab, Pattern, Limit]) ->
    concuerror_sched:notify(ets,
        {match_object, [?LID_FROM_PID(Tab), Tab, Pattern, Limit]}),
    ets:match_object(Tab, Pattern, Limit).

%% ---------------------------
rep_ets_foldl(_Key, _PosArg, [Function, Acc, Tab]) ->
    concuerror_sched:notify(ets,
        {foldl, [?LID_FROM_PID(Tab), Function, Acc, Tab]}),
    ets:foldl(Function, Acc, Tab).

%% ---------------------------
rep_ets_info(_Key, _PosArg, [Tab]) ->
    concuerror_sched:notify(ets,
        {info, [?LID_FROM_PID(Tab), Tab]}),
    ets:info(Tab);
rep_ets_info(_Key, _PosArg, [Tab, Item]) ->
    concuerror_sched:notify(ets,
        {info, [?LID_FROM_PID(Tab), Tab, Item]}),
    ets:info(Tab, Item).

%%%----------------------------------------------------------------------
%%% Helper functions
%%%----------------------------------------------------------------------

find_pid(Pid) when is_pid(Pid) ->
    Pid;
find_pid(Atom) when is_atom(Atom) ->
    whereis(Atom);
find_pid(Other) ->
    Other.
