(* Copyright (c) 2016-2018
 * Evgenii Moiseenko and Anton Podkopaev
 * St.Petersburg State University, JetBrains Research
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *)

open MiniKanren
open MiniKanrenStd

module Injected =
  struct
    type ('tt, 'tl) ti = ('tt, 'tl) MiniKanren.injected
    type ('tt, 'tl) reified = ('tt, 'tl) MiniKanren.reified
  end

module type Logic =
  sig
    type tt

    type tl = inner MiniKanren.logic
      and inner

    type ti = (tt, tl) MiniKanren.injected
    type ri = (tt, tl) MiniKanren.reified

    val reify : MiniKanren.Env.t -> ti -> tl

    val pprint : Format.formatter -> tl -> unit
  end

let rec list_all g xs = conde [
  (xs === nil ());

  fresh (x xs')
    (xs === x % xs')
    (g x)
    (list_all g xs');
]

let rec foldlo ~g ~init ~res xs =
  conde [
    (xs === nil ()) &&& (init === res);
    Fresh.three (fun hd tl acc ->
        (xs === hd % tl) &&&
        (g hd init acc) &&&
        (foldlo tl ~g ~res ~init:acc)
    )
  ]

let rec membero l a =
  Fresh.one (fun xs ->
    (l === a % xs) &&&
    (conde
      [ (xs === nil ())
      ; (xs =/= nil ()) &&& (membero xs a)
      ]
    )
  )

module Trace(T : Logic) =
  struct
    let trace fmt rr = T.pprint fmt @@ rr#reify T.reify
  end

let rec pprint_logic pp ff = function
  | Value x        -> Format.fprintf ff "%a" pp x
  | Var (i, [])    -> Format.fprintf ff "_.%d" i
  | Var (i, ctrs)  ->
    Format.fprintf ff "_.%d{" i;
    List.iter (fun ctr -> Format.fprintf ff "=/= %a; " (pprint_logic pp) ctr) ctrs;
    Format.fprintf ff "}"

let rec pprint_llist' pp ff = function
  | Var (i, ctrs) ->
    Format.fprintf ff "_.%d{" i;
    List.iter (fun ctr -> Format.fprintf ff "=/= %a; " (pprint_llist' pp) ctr) ctrs;
    Format.fprintf ff "}"
  | Value (Cons (x, Value Nil))     -> Format.fprintf ff "%a@;<1>" pp x
  | Value (Cons (x, xs))            -> Format.fprintf ff "%a;@;<1 4>%a" pp x (pprint_llist' pp) xs
  | Value Nil                       -> ()

(* let rec pprint_llist' pp ff xs =
  pprint_logic (pprint_llist'' pp (pprint_llist' pp)) ff xs *)

let pprint_llist_generic fmt fmt_cell pp ff xs =
  Format.fprintf ff fmt (pprint_llist' fmt_cell pp) xs

(* let pprint_llist = pprint_llist_generic "@[<h>[ %a]@]" "%a; %a" *)
let pprint_llist pp ff xs = Format.fprintf ff "@[<hv>[@;<1 4>%a]@]" (pprint_llist' pp) xs

let rec pprint_nat ff n =
  (* try
    match n with
      | Value x        -> Format.fprintf ff "%d" (Nat.to_int @@ Nat.from_logic n)
      | Var (i, [])    -> Format.fprintf ff "_.%d" i
      | Var (i, cstrs)  ->
        Format.fprintf ff "_.%d{" i;
        List.iter (fun cstr -> Format.fprintf ff "=/= %a; " (pprint_nat) cstr) cstrs;
        Format.fprintf ff "}"
    with Not_a_value -> *)
      (* let rec show = fun x -> GT.show(logic) (GT.show(nat) show) x in *)
      Format.fprintf ff "%s" (GT.show(Nat.logic) n)

(*
  let nat_to_str n =
    try
      string_of_int @@ Nat.to_int @@ Nat.from_logic n
    with Not_a_value ->
      let rec show = fun x -> GT.show(logic) (GT.show(lnat) show) x in
      show n
  in
  let pp ff _ = Format.fprintf ff "%s" (nat_to_str n) in
  pprint_logic pp ff n *)

let pprint_string = pprint_logic (fun ff s -> Format.fprintf ff "%s" s)

let zip3 xs ys zs = Stream.map (fun (x, (y, z)) -> (x, y, z)) @@ Stream.zip xs @@ Stream.zip ys zs

let zip4 xs ys zs ws = Stream.map (fun (x, (y, z, w)) -> (x, y, z, w)) @@ Stream.zip xs @@ zip3 ys zs ws

let zip5 xs ys zs ws us = Stream.map (fun (x, (y, z, w, u)) -> (x, y, z, w, u)) @@ Stream.zip xs @@ zip4 ys zs ws us

let zip6 xs ys zs ws us vs = Stream.map (fun (x, (y, z, w, u, v)) -> (x, y, z, w, u, v)) @@ Stream.zip xs @@ zip5 ys zs ws us vs

let rec repeat x n =
  if n <= 0 then [] else x::(repeat x (n-1))

module Option =
  struct
    exception No_value

    let is_some = function
      | Some _  -> true
      | None    -> false

    let is_none = function
      | Some _ -> false
      | None   -> true

    let get = function
      | Some x -> x
      | None   -> raise No_value
  end
