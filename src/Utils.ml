open MiniKanren

let zip3 xs ys zs = Stream.map (fun (x, (y, z)) -> (x, y, z)) @@ Stream.zip xs @@ Stream.zip ys zs

let excl_answ qs = 
  assert ( not (Stream.is_empty qs)); 
  let 
    (hd, tl) = Stream.retrieve ~n:1 qs
  in
    (** We should get deterministic result *)
    (* assert (Stream.is_empty tl); *)
    List.hd hd

let show_assoc show_k show_v lst = 
  let content = List.fold_left (fun ac (k, v) -> ac ^ " {" ^ (show_k k) ^ ": " ^ (show_v v) ^ "}; ") "" lst in
    "{" ^ content ^ "}"

let eq_assoc eq_k eq_v assoc assoc' = 
  let 
    check_exists (k, v) = List.exists (fun (k', v') -> (eq_k k k') && (eq_v v v')) assoc'
  in
    List.for_all check_exists assoc

let inj_assoc inj_k inj_v assoc = MiniKanren.List.inj (fun (k, v) -> !!(inj_k k, inj_v v)) @@ MiniKanren.List.of_list assoc

let prj_pair prj_a prj_b (a, b) = (prj_a a, prj_b b)

let prj_assoc prj_k prj_v assoc = MiniKanren.List.to_list @@ MiniKanren.List.prj (fun lpair -> prj_pair prj_k prj_v @@ !?lpair) assoc

let key_eqo k p b = 
  fresh (k' v')
    (p === !!(k', v'))
    (conde [
      ((k === k') &&& (b === !!true));
      ((k =/= k') &&& (b === !!false)) 
    ])

let key_not_eqo k p b = conde [
    (b === !!true)  &&& (key_eqo k p !!false);
    (b === !!false) &&& (key_eqo k p !!true);
  ] 

let assoco k assocs v =
  fresh (opt) 
    (MiniKanren.List.lookupo (key_eqo k) assocs opt)
    (opt === !!(Some !!(k, v)))

let remove_assoco k assocs assocs' =   
  MiniKanren.List.filtero (key_not_eqo k) assocs assocs'   

let rec update_assoco k v assocs assocs' = conde [
  (assocs === !!MiniKanren.Nil) &&& (assocs' === !!(k, v) % !!MiniKanren.Nil);
  fresh (hd tl tl' k' v')
    (assocs === !!(MiniKanren.Cons (hd, tl)))
    (hd === !!(k', v'))
    (conde [
      (k === k') &&& (assocs' === !!(MiniKanren.Cons (!!(k , v ), tl )));
      (k =/= k') &&& (assocs' === !!(MiniKanren.Cons (!!(k', v'), tl'))) &&& (update_assoco k v tl tl');
    ])
  ]

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
