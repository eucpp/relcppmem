open MiniKanren

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
  | Value (Cons (x, Value Nil))     -> Format.fprintf ff "%a;@;<1>" pp x
  | Value (Cons (x, xs))            -> Format.fprintf ff "%a;@;<1 4>%a" pp x (pprint_llist' pp) xs
  | Value Nil                       -> ()

(* let rec pprint_llist' pp ff xs =
  pprint_logic (pprint_llist'' pp (pprint_llist' pp)) ff xs *)

let pprint_llist_generic fmt fmt_cell pp ff xs =
  Format.fprintf ff fmt (pprint_llist' fmt_cell pp) xs

(* let pprint_llist = pprint_llist_generic "@[<h>[ %a]@]" "%a; %a" *)
let pprint_llist pp ff xs = Format.fprintf ff "@[<hv>[@;<1 4>%a]@]" (pprint_llist' pp) xs

let rec pprint_nat ff n =
  try
    match n with
      | Value x        -> Format.fprintf ff "%d" (Nat.to_int @@ Nat.from_logic n)
      | Var (i, [])    -> Format.fprintf ff "_.%d" i
      | Var (i, cstrs)  ->
        Format.fprintf ff "_.%d{" i;
        List.iter (fun cstr -> Format.fprintf ff "=/= %a; " (pprint_nat) cstr) cstrs;
        Format.fprintf ff "}"
    with Not_a_value ->
      let rec show = fun x -> GT.show(logic) (GT.show(lnat) show) x in
      Format.fprintf ff "%s" (show n)

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
