:- module(query,[
              ask/2
          ]).

/** <module> Query
 *
 * Prolog interface to queries
 *
 * * * * * * * * * * * * * COPYRIGHT NOTICE  * * * * * * * * * * * * * * *
 *                                                                       *
 *  This file is part of TerminusDB.                                     *
 *                                                                       *
 *  TerminusDB is free software: you can redistribute it and/or modify   *
 *  it under the terms of the GNU General Public License as published by *
 *  the Free Software Foundation, under version 3 of the License.        *
 *                                                                       *
 *                                                                       *
 *  TerminusDB is distributed in the hope that it will be useful,        *
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of       *
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the        *
 *  GNU General Public License for more details.                         *
 *                                                                       *
 *  You should have received a copy of the GNU General Public License    *
 *  along with TerminusDB.  If not, see <https://www.gnu.org/licenses/>. *
 *                                                                       *
 * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * */

:- use_module(utils).
:- use_module(database).
:- use_module(woql_compile).
:- use_module(global_prefixes).
:- use_module(descriptor).
:- use_module(types, [is_literal/1]).
:- use_module(literals, [uri_to_prefixed/3]).

:- reexport(woql_term).

/**
 * pre_term_to_term_and_bindings(Pre_Term, Woql_Term, Bindings_In, Bindings_Out) is det.
 *
 * Pre term has free variables that need to be changed into woql variables witha binding
 */
pre_term_to_term_and_bindings(Ctx,Pre_Term,Term,Bindings_In,Bindings_Out) :-
    (   var(Pre_Term)
    ->  (   lookup(V,X,Bindings_In),
            Pre_Term == X
        ->  Bindings_In = Bindings_Out,
            Term = v(V)
        ;   gensym('Var',G),
            Bindings_Out = [var_binding{ var_name : G,
                                         woql_var : Woql_Var}|Bindings_In],
            freeze(Woql_Var,
                   (   Woql_Var = _@_
                   ->  Pre_Term = Woql_Var
                   ;   Woql_Var = Elt^^Type
                   ->  freeze(Type,
                              (   uri_to_prefixed(Type,Ctx,Prefixed_Type),
                                  Pre_Term = Elt^^Prefixed_Type))
                   ;   uri_to_prefixed(Woql_Var,Ctx,Pre_Term))),
            Term = v(G)
        )
    ;   is_dict(Pre_Term)
    ->  Term = Pre_Term,
        Bindings_In=Bindings_Out
    ;   Pre_Term =.. [F|Args],
        mapm(query:pre_term_to_term_and_bindings(Ctx),Args,New_Args,Bindings_In,Bindings_Out),
        Term =.. [F|New_Args]
    ).

collection_descriptor_prefixes(_, Prefixes) :-
    default_prefixes(Prefixes).

/*
 * ask(+Transaction_Object, Pre_Term:Goal) is nondet.
 *
 * Ask a woql query
 */
ask(Query_Context,Pre_Term) :-
    query_context{} :< Query_Context,
    !,
    pre_term_to_term_and_bindings(Query_Context.prefixes,
                                  Pre_Term,Term,
                                  [],Bindings_Out),
    New_Query_Ctx = Query_Context.put(bindings,Bindings_Out),
    compile_query(Term,Prog,New_Query_Ctx,_),
    debug(terminus(sdk),'Program: ~q~n', [Prog]),
    woql_compile:Prog.
ask(Transaction_Object,Pre_Term) :-
    transaction_object{ descriptor : Descriptor } :< Transaction_Object,
    !,
    collection_descriptor_prefixes(Descriptor, Prefixes),
    Query_Context = query_context{
        transaction_objects : [Transaction_Object],
        default_collection : Descriptor,
        prefixes : Prefixes,
        bindings : [],
        selected : []
    },
    ask(Query_Context,Pre_Term).
ask(Collection_Descriptor,Pre_Term) :-
    open_descriptor(Collection_Descriptor, Transaction_Object),
    ask(Transaction_Object, Pre_Term).


ask(Pre_Term) :-
    empty_ctx(Ctx),
    ask(Ctx,Pre_Term).

