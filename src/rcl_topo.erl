%% -*- mode: Erlang; fill-column: 80; comment-column: 75; -*-
%%%-------------------------------------------------------------------
%%% @author Joe Armstrong
%%% @author Eric Merritt
%%% @doc
%%%  This is a pretty simple topological sort for erlang. It was
%%%  originally written for ermake by Joe Armstrong back in '98. It
%%%  has been pretty heavily modified by Eric Merritt since '06 and modified again for Relcool.
%%%
%%%  A partial order on the set S is a set of pairs {Xi,Xj} such that
%%%  some relation between Xi and Xj is obeyed.
%%%
%%%  A topological sort of a partial order is a sequence of elements
%%%  [X1, X2, X3 ...] such that if whenever {Xi, Xj} is in the partial
%%%  order i &lt; j
%%% @end
%%%-------------------------------------------------------------------
-module(rcl_topo).

-export([sort_apps/1,
         format_error/1]).

-include_lib("relcool/include/relcool.hrl").

%%====================================================================
%% Types
%%====================================================================
-type pair() :: {DependentApp::atom(), PrimaryApp::atom()}.
-type name() :: AppName::atom().
-type element() :: name() | pair().

%%====================================================================
%% API
%%====================================================================

%% @doc This only does a topo sort on the list of applications and
%% assumes that there is only *one* version of each app in the list of
%% applications. This implies that you have already done the
%% constraint solve before you pass the list of apps here to be
%% sorted.
-spec sort_apps([rcl_app_info:t()]) ->
                       {ok, [rcl_app_info:t()]} |
                       relcool:error().
sort_apps(Apps) ->
    Pairs = apps_to_pairs(Apps),
    case sort(Pairs) of
        {ok, Names} ->
            {ok, names_to_apps(Names, Apps)};
        E ->
            E
    end.
%% @doc nicely format the error from the sort.
-spec format_error(Reason::term()) -> iolist().
format_error({cycle, Pairs}) ->
    ["Cycle detected in dependency graph, this must be resolved "
     "before we can continue:\n",
    case Pairs of
        [{P1, P2}] ->
            [rcl_util:indent(1), erlang:atom_to_list(P2), "->", erlang:atom_to_list(P1)];
        [{P1, P2} | Rest] ->
            [rcl_util:indent(1), erlang:atom_to_list(P2), "->", erlang:atom_to_list(P1),
             [["-> ", erlang:atom_to_list(PP2), " -> ", erlang:atom_to_list(PP1)] || {PP1, PP2} <- Rest]];
        [] ->
            []
    end].

%%====================================================================
%% Internal Functions
%%====================================================================
%% @doc Do a topological sort on the list of pairs.
-spec sort([pair()]) -> {ok, [atom()]} | relcool:error().
sort(Pairs) ->
    iterate(Pairs, [], all(Pairs)).

-spec names_to_apps([atom()], [rcl_app_info:t()]) -> [rcl_app_info:t()].
names_to_apps(Names, Apps) ->
 [find_app_by_name(Name, Apps) || Name <- Names].

-spec find_app_by_name(atom(), [rcl_app_info:t()]) -> rcl_app_info:t().
find_app_by_name(Name, Apps) ->
    {ok, App1} =
        ec_lists:find(fun(App) ->
                              rcl_app_info:name(App) =:= Name
                      end, Apps),
    App1.

-spec apps_to_pairs([rcl_app_info:t()]) -> [pair()].
apps_to_pairs(Apps) ->
    lists:flatten([app_to_pairs(App) || App <- Apps]).

-spec app_to_pairs(rcl_app_info:t()) -> [pair()].
app_to_pairs(App) ->
    [{DepApp, rcl_app_info:name(App)} ||
        DepApp <-
            rcl_app_info:active_deps(App) ++
            rcl_app_info:library_deps(App)].


%% @doc Iterate over the system.  @private
-spec iterate([pair()], [name()], [name()]) ->
    {ok, [name()]} | relcool:error().
iterate([], L, All) ->
    {ok, remove_duplicates(L ++ subtract(All, L))};
iterate(Pairs, L, All) ->
    case subtract(lhs(Pairs), rhs(Pairs)) of
        []  ->
            ?RCL_ERROR({cycle, Pairs});
        Lhs ->
            iterate(remove_pairs(Lhs, Pairs), L ++ Lhs, All)
    end.

-spec all([pair()]) -> [atom()].
all(L) ->
    lhs(L) ++ rhs(L).

-spec lhs([pair()]) -> [atom()].
lhs(L) ->
    [X || {X, _} <- L].

-spec rhs([pair()]) -> [atom()].
rhs(L) ->
    [Y || {_, Y} <- L].

%% @doc all the elements in L1 which are not in L2
%% @private
-spec subtract([element()], [element()]) -> [element()].
subtract(L1, L2) ->
    [X || X <- L1, not lists:member(X, L2)].

%% @doc remove dups from the list.  @private
-spec remove_duplicates([element()]) -> [element()].
remove_duplicates([H|T]) ->
  case lists:member(H, T) of
      true  ->
          remove_duplicates(T);
      false ->
          [H|remove_duplicates(T)]
  end;
remove_duplicates([]) ->
    [].

%% @doc
%%   removes all pairs from L2 where the first element
%%   of each pair is a member of L1
%%
%%   L2' L1 = [X] L2 = [{X,Y}].
%% @private
-spec remove_pairs([atom()], [pair()]) -> [pair()].
remove_pairs(L1, L2) ->
    [All || All={X, _Y} <- L2, not lists:member(X, L1)].

%%====================================================================
%% Tests
%%====================================================================
-ifndef(NOTEST).
-include_lib("eunit/include/eunit.hrl").

topo_1_test() ->
    Pairs = [{one,two},{two,four},{four,six},
             {two,ten},{four,eight},
             {six,three},{one,three},
             {three,five},{five,eight},
             {seven,five},{seven,nine},
             {nine,four},{nine,ten}],
    ?assertMatch({ok, [one,seven,two,nine,four,six,three,five,eight,ten]},
                 sort(Pairs)).
topo_2_test() ->
    Pairs = [{app2, app1}, {zapp1, app1}, {stdlib, app1},
             {app3, app2}, {kernel, app1}, {kernel, app3},
             {app2, zapp1}, {app3, zapp1}, {zapp2, zapp1}],
    ?assertMatch({ok, [stdlib, kernel, zapp2,
                       app3, app2, zapp1, app1]},
                 sort(Pairs)).

topo_pairs_cycle_test() ->
    Pairs = [{app2, app1}, {app1, app2}, {stdlib, app1}],
    ?assertMatch({error, {_, {cycle, [{app2, app1}, {app1, app2}]}}},
                 sort(Pairs)).

topo_apps_cycle_test() ->
    {ok, App1} = rcl_app_info:new(app1, "0.1", "/no-dir", [app2], [stdlib]),
    {ok, App2} = rcl_app_info:new(app2, "0.1", "/no-dir", [app1], []),
    Apps = [App1, App2],
    ?assertMatch({error, {_, {cycle, [{app2,app1},{app1,app2}]}}},
                 sort_apps(Apps)).

topo_apps_good_test() ->
    Apps = [App ||
               {ok, App} <-
                   [rcl_app_info:new(app1, "0.1", "/no-dir", [app2, zapp1], [stdlib, kernel]),
                    rcl_app_info:new(app2, "0.1", "/no-dir", [app3], []),
                    rcl_app_info:new(app3, "0.1", "/no-dir", [kernel], []),
                    rcl_app_info:new(zapp1, "0.1", "/no-dir", [app2,app3,zapp2], []),
                    rcl_app_info:new(stdlib, "0.1", "/no-dir", [], []),
                    rcl_app_info:new(kernel, "0.1", "/no-dir", [], []),
                    rcl_app_info:new(zapp2, "0.1", "/no-dir", [], [])]],
    {ok, Sorted} = sort_apps(Apps),
    ?assertMatch([stdlib, kernel, zapp2,
                  app3, app2, zapp1, app1],
                 [rcl_app_info:name(App) || App <- Sorted]).

-endif.
