open MiniKanren
open MiniKanrenStd
open Relcppmem
open Relcppmem.Lang
open Relcppmem.Lang.Term
open Relcppmem.Memory

let rules = Rules.Basic.all @ Rules.ThreadSpawning.all @ Rules.SC.all

module SCStep = (val Rules.make_reduction_relation rules)

module Sem = Semantics.Make(SCStep)

let const_hinto t =
  fresh (n)
    (t === const n)

let read_hinto e =
  fresh (mo x)
    (e === read mo x)

let expr_hinto e = conde [
  (read_hinto e);

  (const_hinto e);

  fresh (op e1 e2 n)
    (e  === binop op e1 (const n))
    (read_hinto e1);
]

let write_const_hinto t =
  fresh (mo x n)
    (t === write mo x (const n))

let write_expr_hinto t =
  fresh (mo x e)
    (t === write mo x e)
    (expr_hinto e)

let rec stmt_hinto t = conde [
  (write_const_hinto t);

  (expr_hinto t);

  fresh (t')
    (t === repeat t')
    (expr_hinto t');

  (write_expr_hinto t);

  fresh (t')
    (t === repeat t')
    (seq_stmt_hinto t');

  fresh (cond t1 t2)
    (t === if' cond t1 t2)
    (seq_stmt_hinto t1)
    (seq_stmt_hinto t2);

] and seq_stmt_hinto t = conde [
  (stmt_hinto t);

  fresh (t1 t2)
    (t === seq t1 t2)
    (stmt_hinto t1)
    (conde [
      (stmt_hinto t2);
      (seq_stmt_hinto t2);
    ]);
]

let term_hinto t = conde [expr_hinto t; stmt_hinto t]

let prog_MUTEX = fun h1 h2 h3 h4 -> <:cppmem<
    spw {{{
        ? h1;
        if ? h2 then
          ret 1
        else
          ret 0
        fi
    |||
        ? h3;
        if ? h4 then
          ret 1
        else
          ret 0
        fi
    }}}
>>

(* let prog_MUTEX = <:cppmem<
    spw {{{
        x_sc := 0;
        if x_sc then
          ret 1
        else
          ret 0
        fi
    |||
        x_sc := 1;
        if x_sc != 1 then
          ret 1
        else
          ret 0
        fi
    }}}
>> *)

let int_of_bool b = if b then 1 else 0

let ret n = const @@ Nat.inj @@ Nat.of_int n

let pair (x, y) = pair (ret x) (ret y)

let _ =
  let term = prog_MUTEX in
  let state = MemState.inj @@ MemState.preallocate [] ["x"; "y";] in
  let stream = Sem.(
    run q
      (fun prog ->
        fresh (h1 h2 h3 h4 state1 state2)
          (term_hinto h1)
          (expr_hinto h2)
          (term_hinto h3)
          (expr_hinto h4)
          (prog === term h1 h2 h3 h4)
          ((prog, state) -->* (pair (1, 0), state1))
          ((prog, state) -->* (pair (0, 1), state2))
          (negation (
            fresh (state')
              ((prog, state) -->* (pair (1, 1), state'))
          ))
      )
      (fun progs -> Stream.map (Term.refine) progs)
      (* (fun progs ->
        let pred prog = Sem.(
          run q
            (fun q ->
              fresh (state')
                (q === pair (1, 1))
                ((Term.inj prog, state) -->* (q, state'))
            )
            (fun qs -> Stream.is_empty qs)
        ) in
        Stream.filter pred @@ Stream.map (fun rr -> rr#prj) progs
      ) *)
    (* run qr
      (fun q r ->
        fresh (s1 s2)
          ((prog_MUTEX, state) -->* (q, r)) *)
          (* ((prog_MUTEX, state) -->* (pair (1, 0), s1))
          ((prog_MUTEX, state) -->* (pair (0, 1), s2))
          (negation (
            fresh (state')
              ((prog_MUTEX, state) -->* (pair (1, 1), state'))
          ))
      ) *)
      (* (fun qs rs -> Stream.zip (Stream.map (Term.refine) qs) (Stream.map (MemState.refine) rs)) *)
  ) in
  let printer prog =
  (* let printer (q, r) = *)
    Printf.printf "\n---------------------------------\n";
    Printf.printf "prog: %s\n" (Term.pprint prog);
    (* Printf.printf "\n%s\n%s\n" (Term.pprint q) (MemState.pprint r); *)
    Printf.printf "\n---------------------------------\n";
  in
  List.iter printer @@ Stream.take ~n:1 stream
