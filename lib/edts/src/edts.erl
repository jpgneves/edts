%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @doc
%%% @end
%%% @author Thomas Järvstrand <tjarvstrand@gmail.com>
%%% @copyright
%%% Copyright 2012 Thomas Järvstrand <tjarvstrand@gmail.com>
%%%
%%% This file is part of EDTS.
%%%
%%% EDTS is free software: you can redistribute it and/or modify
%%% it under the terms of the GNU Lesser General Public License as published by
%%% the Free Software Foundation, either version 3 of the License, or
%%% (at your option) any later version.
%%%
%%% EDTS is distributed in the hope that it will be useful,
%%% but WITHOUT ANY WARRANTY; without even the implied warranty of
%%% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%%% GNU Lesser General Public License for more details.
%%%
%%% You should have received a copy of the GNU Lesser General Public License
%%% along with EDTS. If not, see <http://www.gnu.org/licenses/>.
%%% @end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%_* Module declaration =======================================================
-module(edts).

%%%_* Exports ==================================================================

%% API
-export([ compile_and_load/2
        , continue/1
        , get_function_info/4
        , get_module_info/3
        , init_node/1
        , interpret_modules/2
        , is_node/1
        , node_available_p/1
        , modules/1
        , node_reachable/1
        , nodes/0
        , step/1
        , toggle_breakpoint/3
        , trace_function/3
        , wait_for_debugger/2
        , who_calls/4]).

%%%_* Includes =================================================================

%%%_* Defines ==================================================================

%%%_* Types ====================================================================

%%%_* API ======================================================================

%%------------------------------------------------------------------------------
%% @doc
%% Compiles Module on Node and returns a list of any errors and warnings.
%% If there are no errors, the module will be loaded.
%% @end
-spec compile_and_load(Node::node(), Filename::file:filename()) ->
                          [term()] | {error, not_found}.
%%------------------------------------------------------------------------------
compile_and_load(Node, Filename) ->
  lager:debug("compile_and_load ~p on ~p", [Filename, Node]),
  edts_server:ensure_node_initialized(Node),
  case edts_dist:call(Node, edts_code, compile_and_load, [Filename]) of
    {badrpc, _} -> {error, not_found};
    Result      -> Result
  end.

%%------------------------------------------------------------------------------
%% @doc
%% Returns information about Module:Function/Arity on Node.
%% @end
%%
-spec get_function_info( Node    ::node()
                       , Module  ::module()
                       , Function::atom()
                       , Arity   ::non_neg_integer()) ->
                           [{atom(), term()}] | {error, not_found}.
%%------------------------------------------------------------------------------
get_function_info(Node, Module, Function, Arity) ->
  lager:debug("get_function info ~p:~p/~p on ~p",
              [Module, Function, Arity, Node]),
  Args = [Module, Function, Arity],
  case edts_dist:call(Node, edts_code, get_function_info, Args) of
    {badrpc, _} -> {error, not_found};
    Info  -> Info
  end.

%%------------------------------------------------------------------------------
%% @doc
%% Returns a list of the functions calling Module:Function/Arity on Node.
%% @end
%%
-spec who_calls( Node    ::node()
               , Module  ::module()
               , Function::atom()
               , Arity   ::non_neg_integer()) ->
                   [{module(), atom(), term()}].
%%------------------------------------------------------------------------------
who_calls(Node, Module, Function, Arity) ->
  edts_server:ensure_node_initialized(Node),
  Args = [Module, Function, Arity],
  case edts_dist:call(Node, edts_code, who_calls, Args) of
    {badrpc, _} -> {error, not_found};
    Info  -> Info
  end.

%%------------------------------------------------------------------------------
%% @doc
%% Returns the result of running Trace on Node, using Opts.
%% @end
%%
-spec trace_function( Node   :: node()
                    , Trace  :: send | 'receive' | string()
                    , Opts   :: [{atom(), any()}]) ->
                        string() | {error, not_found}.
%%------------------------------------------------------------------------------
trace_function(Node, Trace, Opts0) ->
  TraceLog = spawn_monitor(fun edts_dbg:receive_traces/0),
  Opts = Opts0 ++ [{print_pid, TraceLog}],
  Args = [Trace, Opts],
  Result = case edts_dist:call(Node, edts_dbg, trace_function, Args) of
             {badrpc, _} -> {error, not_found};
             TraceResult -> TraceResult
           end,
  receive
    {'DOWN', _, _, _, Reason} -> io:format("Tracing finished: ~p~n", [Reason]),
                                 Result
  end.

%%------------------------------------------------------------------------------
%% @doc
%% Interprets Modules in Node, if possible, returning the list of interpreted
%% modules.
%% @end
-spec interpret_modules( Node :: node()
                       , Modules :: [module()] ) ->
                           [module()] | {error, not_found}.
%%------------------------------------------------------------------------------
interpret_modules(Node, Modules) ->
  case edts_dist:call(Node, edts_debug_server, interpret_modules, [Modules]) of
    {badrpc, _} -> {error, not_found};
    Interpreted -> Interpreted
  end.

%%------------------------------------------------------------------------------
%% @doc
%% Toggles a breakpoint in Module:Line at Node.
%% @end
-spec toggle_breakpoint( Node :: node()
                       , Module :: module()
                       , Line :: non_neg_integer()) ->
                           {ok, set, {Module, Line}}
                         | {ok, unset, {Module, Line}}
                         | {error, not_found}.
%%------------------------------------------------------------------------------
toggle_breakpoint(Node, Module, Line) ->
  Args = [Module, Line],
  case edts_dist:call(Node, edts_debug_server, toggle_breakpoint, Args) of
    {badrpc, _} -> {error, not_found};
    Result      -> Result
  end.


%%------------------------------------------------------------------------------
%% @doc
%% Step through in execution while debugging, in Node.
%% @end
-spec step(Node :: node()) -> ok | {error, not_found}.
%%------------------------------------------------------------------------------
step(Node) ->
  case edts_dist:call(Node, edts_debug_server, step, []) of
    {badrpc, _} -> {error, not_found};
    Result      -> Result
  end.

%%------------------------------------------------------------------------------
%% @doc
%% Continue execution until a breakpoint is hit or execution terminates.
%% @end
-spec continue(Node :: node()) -> ok | {error, not_found}.
%%------------------------------------------------------------------------------
continue(Node) ->
  case edts_dist:call(Node, edts_debug_server, continue, []) of
    {badrpc, _} -> {error, not_found};
    Result      -> Result
  end.

%%------------------------------------------------------------------------------
%% @doc
%% Wait for debugger to attach, for a maximum of Attempts.
%% @end
-spec wait_for_debugger(Node :: node(), Attempts :: non_neg_integer()) ->
                           ok | {error, attempts_exceeded}.
%%------------------------------------------------------------------------------
wait_for_debugger(_, 0) ->
  io:format("Debugger not up. Giving up...~n"),
  {error, attempts_exceeded};
wait_for_debugger(Node, Attempts) ->
  RemoteRegistered = rpc:call(Node, erlang, registered, []),
  case lists:member(edts_debug_server, RemoteRegistered) of
    true ->
      io:format("Debugger up!~n"),
      io:format("Ordering debugger to continue...~n"),
      edts_dist:call(Node, edts_debug_server, continue, []),
      ok;
    _    ->
      io:format("Debugger not up yet... Trying ~p more time(s)~n", [Attempts]),
      timer:sleep(1000),
      wait_for_debugger(Node, Attempts - 1)
  end.

%%------------------------------------------------------------------------------
%% @doc
%% Returns information about Module on Node.
%% @end
%%
-spec get_module_info(Node::node(), Module::module(),
                      Level::detailed | basic) ->
                         {ok, [{atom(), term()}]}.
%%------------------------------------------------------------------------------
get_module_info(Node, Module, Level) ->
  lager:debug("get_module_info ~p, ~p on ~p", [Module, Level, Node]),
  case edts_dist:call(Node, edts_code, get_module_info, [Module, Level]) of
    {badrpc, _} -> {error, not_found};
    Info  -> Info
  end.

%%------------------------------------------------------------------------------
%% @doc
%% Initializes a new edts node.
%% @end
%%
-spec init_node(Node::node()) -> ok.
%%------------------------------------------------------------------------------
init_node(Node) ->
  edts_server:init_node(Node).

%%------------------------------------------------------------------------------
%% @doc
%% Returns true iff Node is registered with this edts instance.
%% @end
%%
-spec is_node(Node::node()) -> boolean().
%%------------------------------------------------------------------------------
is_node(Node) ->
  edts_server:is_node(Node).

%%------------------------------------------------------------------------------
%% @doc
%% Returns true iff Node is registered with this edts instance and has fisished
%% its initialization.
%% @end
%%
-spec node_available_p(Node::node()) -> boolean().
%%------------------------------------------------------------------------------
node_available_p(Node) ->
  edts_server:node_available_p(Node).


%%------------------------------------------------------------------------------
%% @doc
%% Returns a list of all erlang modules available on Node.
%% @end
%%
-spec modules(Node::node()) -> [module()].
%%------------------------------------------------------------------------------
modules(Node) ->
  edts_server:ensure_node_initialized(Node),
  edts_dist:call(Node, edts_code, modules).


%%------------------------------------------------------------------------------
%% @doc
%% Returns true if Node is registerend with the epmd on localhost.
%% @end
%%
-spec node_reachable(Node::node()) -> boolean().
%%------------------------------------------------------------------------------
node_reachable(Node) ->
  case net_adm:ping(Node) of
    pong -> true;
    pang -> false
  end.

%%------------------------------------------------------------------------------
%% @doc
%% Returns a list of the edts_nodes currently registered with this
%% edts-instance.
%% @end
%%
-spec nodes() -> [node()].
%%------------------------------------------------------------------------------
nodes() ->
  edts_server:nodes().

%%%_* Internal functions =======================================================

%%%_* Emacs ====================================================================
%%% Local Variables:
%%% allout-layout: t
%%% erlang-indent-level: 2
%%% End:
