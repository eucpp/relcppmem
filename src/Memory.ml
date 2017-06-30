open MiniKanren
open MiniKanrenStd
open Utils

module Loc =
  struct
    type tt = string
    type tl = string MiniKanren.logic
    type ti = (tt, tl) MiniKanren.injected

    let of_string str = str
    let to_string loc = loc

    let inj = (!!)

    let to_logic x = Value x

    let show = GT.show(logic) (GT.show(GT.string))
  end

module Var =
  struct
    type tt = string
    type tl = string MiniKanren.logic
    type ti = (tt, tl) MiniKanren.injected

    let of_string str = str
    let to_string loc = loc

    let inj = (!!)

    let to_logic x = Value x

    let show = GT.show(logic) (GT.show(GT.string))
  end

module Value =
  struct
    type tt = MiniKanrenStd.Nat.ground
    type tl = MiniKanrenStd.Nat.logic
    type ti = MiniKanrenStd.Nat.groundi

    let of_string str = Nat.of_int @@ int_of_string str

    let to_string v = string_of_int @@ Nat.to_int v

    let inj = Nat.inj

    let to_logic = Nat.to_logic

    let show = GT.show(Nat.logic)
  end

module Timestamp =
  struct
    type tt = MiniKanrenStd.Nat.ground
    type tl = MiniKanrenStd.Nat.logic
    type ti = MiniKanrenStd.Nat.groundi
  end

module MemOrder =
  struct
    type tt = SC | ACQ | REL | ACQ_REL | CON | RLX | NA
    type tl = tt MiniKanren.logic
    type ti = (tt, tl) MiniKanren.injected

    let of_string str =
      let binding = [("sc", SC);
                     ("acq", ACQ);
                     ("rel", REL);
                     ("relAcq", ACQ_REL);
                     ("con", CON);
                     ("rlx", RLX);
                     ("na", NA)]
      in
      List.assoc str binding

    let to_string = function
      | SC      -> "sc"
      | ACQ     -> "acq"
      | REL     -> "rel"
      | ACQ_REL -> "relAcq"
      | CON     -> "con"
      | RLX     -> "rlx"
      | NA      -> "na"

    let inj = (!!)

    let show = GT.show(logic) (to_string)
  end

module Path =
  struct
    module T =
      struct
        type 'a t = N | L of 'a | R of 'a

        let fmap ft = function
          | N   -> N
          | L p -> L (ft p)
          | R p -> R (ft p)
      end

    type tt = tt T.t
    type tl = tl T.t logic
    type ti = (tt, tl) injected

    include Fmap1(T)

    let inj' = inj

    let rec inj p = inj' @@ distrib (T.fmap (inj) p)

    let pathn ()  = inj' @@ distrib @@ T.N
    let pathl p   = inj' @@ distrib @@ T.L p
    let pathr p   = inj' @@ distrib @@ T.R p
  end

module Registers =
  struct
    type tt = (Var.tt, Value.tt) VarList.tt
    type tl = (Var.tl, Value.tl) VarList.tl
    type ti = (Var.tt, Value.tt, Var.tl, Value.tl) VarList.ti

    let inj = List.inj (fun (var, value) -> inj_pair (!!var) (Nat.inj value))

    let to_logic = List.to_logic (fun (var, value) -> Value (Value var, Nat.to_logic value))

    let reify h = ManualReifiers.(List.reify (pair (string) (Nat.reify)) h)

    let allocate vars = List.of_list (fun s -> (s, Nat.of_int 0)) vars

    let reset_varo p p' = Nat.(
      fresh (var value)
        (p  === inj_pair var value)
        (p' === inj_pair var (inj_nat 0))
      )

    let reseto = VarList.mapo reset_varo

    let printer =
      let pp ff (var, value) = Format.fprintf ff "%a=%a" pprint_string var pprint_nat value in
      let ppl = pprint_logic pp in
      pprint_llist ppl

    let pprint xs =
      printer Format.str_formatter xs;
      Format.flush_str_formatter ()

  end

module ViewFront =
  struct
    type tt = (Loc.tt, Timestamp.tt) VarList.tt
    type tl = (Loc.tl, Timestamp.tl) VarList.tl
    type ti = (Loc.tt, Timestamp.tt, Loc.tl, Timestamp.tl) VarList.ti

    let inj = List.inj (fun (var, value) -> inj_pair (!!var) (Nat.inj value))

    let to_logic = List.to_logic (fun (loc, ts) -> Value (Value loc, Nat.to_logic ts))

    let reify h = ManualReifiers.(List.reify (pair (string) (Nat.reify)) h)

    let allocate atomics = List.of_list (fun s -> (s, Nat.of_int 0)) atomics

    let from_list lst = List.of_list (fun (s, v) -> (s, Nat.of_int v)) lst

    let reset_tso p p' = Nat.(
      fresh (loc ts)
        (p  === inj_pair loc ts)
        (p' === inj_pair loc (inj_nat 0))
      )

    let reseto = VarList.mapo reset_tso

    let rec updateo t t' loc' ts' = Nat.(
      fresh (hd tl tl' loc ts)
        (t  === hd % tl)
        (hd === inj_pair loc ts)
        (conde [
          (loc === loc') &&& (conde [
            (ts' >  ts) &&& (t' === (inj_pair loc' ts') % tl);
            (ts' <= ts) &&& (t' === t);
          ]);
          (loc =/= loc') &&& (t' === hd % tl') &&& (updateo tl tl' loc' ts');
        ])
      )

    let mergeo t1 t2 t = VarList.map2o VarList.join_tso t1 t2 t

    let printer =
      let pp ff (var, value) = Format.fprintf ff "%a@%a" pprint_string var pprint_nat value in
      let ppl = pprint_logic pp in
      pprint_llist ppl

    let pprint xs =
      printer Format.str_formatter xs;
      Format.flush_str_formatter ()

  end

module Promise =
  struct
    module T = struct
      type ('a, 'b, 'c, 'd) t = 'a * 'b * 'c * 'd

      let fmap fa fb fc fd (a, b, c, d) = (fa a, fb b, fc c, fd d)
    end

    type tt = (Loc.tt, Timestamp.tt, Value.tt, ViewFront.tt) T.t
    type tl = (Loc.tl, Timestamp.tl, Value.tl, ViewFront.tl) T.t MiniKanren.logic
    type ti = (tt, tl) MiniKanren.injected

    include Fmap4(T)

    let promise loc ts value vf =
      inj @@ distrib @@ (loc, ts, value, vf)

    let inj (loc, ts, value, vf) =
      promise (!!loc) (Nat.inj ts) (Nat.inj value) (ViewFront.inj vf)

    let to_logic (loc, ts, value, vf) = Value (Loc.to_logic loc, Nat.to_logic ts, Nat.to_logic value, ViewFront.to_logic vf)

    let reify = reify ManualReifiers.string Nat.reify Nat.reify ViewFront.reify

    let printer =
      let pp ff (loc, ts, value, vf) =
        Format.fprintf ff "@[<h>{%a@%a=%a, %a}@]"
          pprint_string loc
          pprint_nat ts
          pprint_nat value
          ViewFront.printer vf
      in
      pprint_logic pp

  end

module PromiseSet =
  struct
    type tt = Promise.tt List.ground
    type tl = Promise.tl List.logic
    type ti = (Promise.tt, Promise.tl) List.groundi

    let inj = List.inj (Promise.inj)

    let to_logic = List.to_logic (Promise.to_logic)

    let reify = List.reify (Promise.reify)

    let printer =
      pprint_llist Promise.printer

  end

module ThreadState =
  struct
    module T = struct
      type ('a, 'b, 'c, 'd, 'e) t = {
        regs : 'a;
        curr : 'b;
        rel  : 'c;
        acq  : 'd;
        prm  : 'e;
      }

      let fmap fa fb fc fd fe {regs = a; curr = b; rel = c; acq = d; prm = e} =
        {regs = fa a; curr = fb b; rel = fc c; acq = fd d; prm = fe e}
    end

    type tt = (Registers.tt, ViewFront.tt, ViewFront.tt, ViewFront.tt, PromiseSet.tt) T.t

    type tl_inner = (Registers.tl, ViewFront.tl, ViewFront.tl, ViewFront.tl, PromiseSet.tl) T.t

    type tl = tl_inner MiniKanren.logic

    type ti = (tt, tl) MiniKanren.injected

    include Fmap5(T)

    let thrd_state regs curr rel acq prm =
      inj @@ distrib @@ {T.regs = regs; T.curr = curr; T.rel = rel; T.acq = acq; T.prm = prm }

    let inj {T.regs = regs; T.curr = curr; T.rel = rel; T.acq = acq; T.prm = prm } =
      thrd_state (Registers.inj regs) (ViewFront.inj curr) (ViewFront.inj rel) (ViewFront.inj acq) (PromiseSet.inj prm)

    let to_logic { T.regs = regs; T.curr = curr; T.rel = rel; T.acq = acq; T.prm = prm } =
      Value {
        T.regs = Registers.to_logic regs;
        T.curr = ViewFront.to_logic curr;
        T.rel  = ViewFront.to_logic rel;
        T.acq  = ViewFront.to_logic acq;
        T.prm  = PromiseSet.to_logic prm;
      }

    let reify h = reify Registers.reify ViewFront.reify ViewFront.reify ViewFront.reify PromiseSet.reify h

    let convert = (fun (var, value) -> (var, Nat.of_int value))

    let create ?(rel) ?(acq) vars curr =
      let rel = match rel with
        | Some rel -> rel
        | None     -> curr
      in
      let acq = match acq with
        | Some acq -> acq
        | None     -> curr
      in {
      T.regs = List.of_list convert vars;
      T.curr = List.of_list convert curr;
      T.rel  = List.of_list convert rel;
      T.acq  = List.of_list convert acq;
      T.prm  = Nil;
    }

    let preallocate vars atomics = {
      T.regs = Registers.allocate vars;
      T.curr = ViewFront.allocate atomics;
      T.rel  = ViewFront.allocate atomics;
      T.acq  = ViewFront.allocate atomics;
      T.prm  = Nil;
    }

    let printer =
      let pp ff {T.regs = regs; T.curr = curr; T.rel = rel; T.acq = acq; T.prm = prm } =
        Format.fprintf ff "@[<v>reg: %a @; cur: %a @; acq: %a @; rel: %a @; prm: %a @]"
          Registers.printer regs
          ViewFront.printer curr
          ViewFront.printer acq
          ViewFront.printer rel
          PromiseSet.printer prm
      in
      pprint_logic pp

    let pprint thrd =
      printer Format.str_formatter thrd;
      Format.flush_str_formatter ()

    let get_varo thrd var value =
      fresh (regs curr rel acq prm)
        (thrd === thrd_state regs curr rel acq prm)
        (VarList.geto regs var value)

    let set_varo thrd thrd' var value =
      fresh (regs regs' curr rel acq prm)
        (thrd  === thrd_state regs  curr rel acq prm)
        (thrd' === thrd_state regs' curr rel acq prm)
        (VarList.seto regs regs' var value)

    let tso thrd loc ts =
      fresh (regs curr rel acq prm)
        (thrd === thrd_state regs curr rel acq prm)
        (VarList.geto curr loc ts)

    let updateo thrd thrd' loc ts =
      fresh (regs curr curr' rel acq acq' prm)
        (thrd  === thrd_state regs curr  rel  acq  prm)
        (thrd' === thrd_state regs curr' rel  acq' prm)
        (ViewFront.updateo curr curr' loc ts)
        (* (VarList.seto rel  rel'  loc ts) *)
        (ViewFront.updateo acq  acq'  loc ts)

    let front_relo thrd loc rel =
      fresh (regs curr acq prm)
        (thrd === thrd_state regs curr rel acq prm)

    let update_acqo thrd thrd' vf =
      fresh (regs curr rel acq acq' prm)
        (thrd  === thrd_state regs curr rel acq  prm)
        (thrd' === thrd_state regs curr rel acq' prm)
        (ViewFront.mergeo vf acq acq')

    let fence_acqo thrd thrd' =
      fresh (regs curr rel acq prm)
        (thrd  === thrd_state regs curr rel acq prm)
        (thrd' === thrd_state regs acq  rel acq prm)

    let fence_loc_relo thrd thrd' loc =
      fresh (regs curr rel acq prm)
        (thrd  === thrd_state regs curr rel  acq prm)
        (thrd' === thrd_state regs curr curr acq prm)

    let fence_relo thrd thrd' =
      fresh (regs curr rel acq prm)
        (thrd  === thrd_state regs curr rel  acq prm)
        (thrd' === thrd_state regs curr curr acq prm)

    let promiseo thrd thrd' loc ts value vf =
      fresh (regs curr rel acq prm prm' p)
        (thrd  === thrd_state regs curr rel  acq prm )
        (thrd' === thrd_state regs curr curr acq prm')
        (p === Promise.promise loc ts value vf)
        (prm' === p % prm)

    (* let betweeno ts_lb ts_ub ts =
      fresh (sum n d d')
        (Rational.lto ts_lb ts_ub !!true)
        (ts  === n %% d')
        (sum === n %% d )
        (Rational.addo ts_lb ts_ub sum)
        (Nat.mulo d 2 d') *)

    let removeo prm prm' p =
      let pred p' b = conde [
        (p =/= p') &&& (b === !!true);
        (p === p') &&& (b === !!false);
      ] in
      List.filtero pred prm prm'

    let fulfillo thrd thrd'' = Nat.(
      fresh (thrd' regs curr rel acq prm prm' p loc ts last_ts value vf)
        (thrd  === thrd_state regs curr rel acq prm )
        (thrd' === thrd_state regs curr rel acq prm')
        (List.membero prm p)
        (p === Promise.promise loc ts value vf)
        (tso thrd loc last_ts)
        (last_ts < ts)
        (* (vf === rel) *)
        (removeo prm prm' p)
        (updateo thrd' thrd'' loc ts)
      )

    let laggingo thrd b =
      fresh (regs curr rel acq prm)
        (thrd === thrd_state regs curr rel acq prm)
        (conde [
          (prm =/= inj_listi []) &&& (b === !!true);
          (prm === inj_listi []) &&& (b === !!false);
        ])

    let certifyo thrd =
      fresh (regs curr rel acq prm)
        (thrd  === thrd_state regs curr rel acq prm)
        (prm   === nil ())

    let spawno thrd child1 child2 =
      fresh (regs regs' curr rel acq)
        (thrd   === thrd_state regs  curr rel acq (nil ()))
        (child1 === thrd_state regs' curr rel acq (nil ()))
        (child1 === child2)
        (Registers.reseto regs regs')

    let joino thrd thrd' child1 child2 =
      fresh (regs       regs1 regs2
             curr curr' curr1 curr2
             rel  rel' rel1 rel2
             acq  acq' acq1 acq2
             prm prm1 prm2)
        (thrd   === thrd_state regs  curr  rel  acq  (nil ()))
        (thrd'  === thrd_state regs  curr' rel' acq' (nil ()))
        (child1 === thrd_state regs1 curr1 rel1 acq1 (nil ()))
        (child2 === thrd_state regs2 curr2 rel2 acq2 (nil ()))
        (ViewFront.mergeo curr1 curr2 curr')
        (ViewFront.mergeo rel1  rel2  rel' )
        (ViewFront.mergeo acq1  acq2  acq' )
        (* (List.appendo prm1 prm2 prm) *)

  end

module Threads =
  struct
    module Tree =
      struct
        type ('a, 't) t =
          | Nil
          | Node of 'a * 't * 't

        let fmap fa ft = function
          | Nil            -> Nil
          | Node (a, l, r) -> Node (fa a, ft l, ft r)
      end

    type tt = (ThreadState.tt, tt) Tree.t
    type tl = (ThreadState.tl, tl) Tree.t MiniKanren.logic
    type ti = (tt, tl) MiniKanren.injected

    include Fmap2(Tree)

    let nil        = inj @@ distrib @@ Tree.Nil
    let node a l r = inj @@ distrib @@ Tree.Node (a, l, r)
    let leaf a     = inj @@ distrib @@ Tree.Node (a, nil, nil)

    let inj' = inj

    let rec inj tree = inj' @@ distrib (Tree.fmap (ThreadState.inj) (inj) tree)

    let rec to_logic tree = Value (Tree.fmap (ThreadState.to_logic) (to_logic) tree)

    let reify' = reify

    let rec reify h = reify' ThreadState.reify reify h

    let create ?rel ?acq vars curr =
      Tree.Node (ThreadState.create ?rel ?acq vars curr, Tree.Nil, Tree.Nil)

    let threads_list thrd_tree =
      let q = Queue.create () in
      let lst = ref [] in
      Queue.push thrd_tree q;
      while not @@ Queue.is_empty q do
        match Queue.pop q with
        | Value (Tree.Node (thrd, l, r)) ->
          lst := thrd :: !lst;
          Queue.push l q;
          Queue.push r q
        | Value Tree.Nil  -> ()
        | Var (i, _) ->
          lst := (Var (i, [])) :: !lst
      done;
      List.rev !lst

    let printer ff thrd_tree =
      let cnt = ref 1 in
      let pp ff thrd =
        Format.fprintf ff "@[<v>Thread %d:@;<1 4>%a@;@]" !cnt ThreadState.printer thrd;
        cnt := !cnt + 1
      in
      List.iter (pp ff) @@ threads_list thrd_tree

    let pprint thrd_tree =
      printer (Format.str_formatter) thrd_tree;
      Format.flush_str_formatter ()

    let rec geto tree path thrd = Path.(
      fresh (thrd' l r path')
        (tree === node thrd' l r)
        (conde [
          (path === pathn ()) &&& (thrd === thrd');
          (conde [
            (path === pathl path') &&& (geto l path' thrd);
            (path === pathr path') &&& (geto r path' thrd);
          ])
        ])
      )

    let rec seto tree tree' path thrd_new = Path.(
      fresh (thrd thrd' path' l l' r r')
        (tree  === node thrd  l  r )
        (tree' === node thrd' l' r')
        (conde [
          (path === pathn ()) &&& (thrd' === thrd_new) &&&
          (l === l') &&& (r === r');

          (thrd' === thrd) &&&
          (conde [
            (path === pathl path') &&& (r === r') &&& (seto l l' path' thrd_new);
            (path === pathr path') &&& (l === l') &&& (seto r r' path' thrd_new);
          ])
        ])
      )

    let rec laggingo tree b =
      fresh (thrd l r b1 b2)
        (conde [
            (tree === leaf thrd) &&&
            (ThreadState.laggingo thrd b);

            (tree =/= leaf thrd) &&&
            (tree === node thrd l r) &&&
            (laggingo l b1) &&&
            (laggingo r b2) &&&
            (MiniKanrenStd.Bool.oro b1 b2 b);
        ])

    let rec spawno tree tree' path = Path.(
      fresh (thrd l l' r r' path')
        (tree  === node thrd  l  r )
        (tree' === node thrd  l' r')
        (conde [
          fresh (a b)
            (path === pathn ())
            (l  === nil)
            (r  === nil)
            (l' === leaf a)
            (r' === leaf b)
            (ThreadState.spawno thrd a b);

          (conde [
            (path === pathl path') &&& (spawno l l' path') &&& (r === r');
            (path === pathr path') &&& (spawno r r' path') &&& (l === l');
          ])
        ])
      )

    let rec joino tree tree' path = Path.(
      fresh (thrd thrd' l l' r r' path')
        (tree  === node thrd  l  r )
        (tree' === node thrd' l' r')
        (conde [
          fresh (a b)
            (path  === pathn ())
            (l  === leaf a)
            (r  === leaf b)
            (l' === nil)
            (r' === nil)
            (ThreadState.joino thrd thrd' a b);

          (thrd === thrd') &&&
          (conde [
            (path === pathl path') &&& (r === r') &&& (joino l l' path');
            (path === pathr path') &&& (l === l') &&& (joino r r' path');
          ]);
        ])
      )
  end

module LocStory =
  struct
    module Cell = struct
      type tt = (Timestamp.tt * Value.tt * ViewFront.tt)
      type tl = (Timestamp.tl * Value.tl * ViewFront.tl) logic
      type ti = (tt, tl) injected

      let inj (ts, value, vf) =
        inj_triple (inj_nat @@ Nat.to_int ts) (inj_nat @@ Nat.to_int value) (ViewFront.inj vf)

      let to_logic (ts, value, vf) = Value (Nat.to_logic ts, Nat.to_logic value, ViewFront.to_logic vf)

      let reify = ManualReifiers.triple Nat.reify Nat.reify ViewFront.reify

      let printer var =
        let pp ff (ts, value, vf) =
          Format.fprintf ff "@[<h>{%a@%a=%a, %a}@]"
            pprint_string var
            pprint_nat ts
            pprint_nat value
            ViewFront.printer vf
        in
        pprint_logic pp
    end

    module T = struct
      type ('a, 'b) t = {
        tsnext : 'a;
        story  : 'b;
      }

      let fmap fa fb {tsnext = a; story = b} = {tsnext = fa a; story = fb b}
    end

    type tt = (Nat.ground, Cell.tt List.ground) T.t
    type tl_inner = (Nat.logic, Cell.tl List.logic) T.t
    type tl = tl_inner MiniKanren.logic
    type ti = (tt, tl) MiniKanren.injected

    include Fmap2(T)

    let loc_story tsnext story = inj @@ distrib @@ {T.tsnext = tsnext; T.story = story}

    let inj {T.tsnext = tsnext; T.story = story} = loc_story (inj_nat @@ Nat.to_int tsnext) (List.inj (Cell.inj) story)

    let to_logic {T.tsnext = tsnext; T.story = story} =
      Value {T.tsnext = Nat.to_logic tsnext; T.story = List.to_logic Cell.to_logic story}

    let reify h = reify Nat.reify (List.reify Cell.reify) h

    let create tsnext story = {
      T.tsnext = Nat.of_int tsnext;
      T.story  = List.of_list (fun (ts, v, vf) -> (Nat.of_int ts, Nat.of_int v, vf)) story;
    }

    let preallocate atomics =
      let vf = ViewFront.allocate atomics in
      create 1 [(0, 0, vf)]

    let printer var =
      let pp ff {T.story = story} =
        pprint_llist (Cell.printer var) ff story
      in
      pprint_logic pp

    let pprint var story =
      printer var Format.str_formatter story;
      Format.flush_str_formatter ()

    let last_tso t ts =
      fresh (ts' story)
        (t   === loc_story ts' story)
        (ts' === Nat.succ ts)

    let next_tso t ts =
      fresh (story)
        (t === loc_story ts story)

    let visibleo ts msg b =
      fresh (ts' value vf)
        (msg === inj_triple ts' value vf)
        (Nat.leo ts ts' b)

    let reado t last_ts ts value vf =
      fresh (story tsnext visible msg)
        (t === loc_story tsnext story)
        (MiniKanrenStd.List.filtero (visibleo last_ts) story visible)
        (MiniKanrenStd.List.membero visible msg)
        (msg === inj_triple ts value vf)

    let writeo t t' value vf =
      fresh (ts ts' story story')
        (t  === loc_story ts  story )
        (t' === loc_story ts' story')
        (ts' === Nat.succ ts)
        (story' === (inj_triple ts value vf) % story)

    let last_valueo t value =
      fresh (ts ts' story msg tail vf)
        (t   === loc_story  ts  story)
        (msg === inj_triple ts' value vf)
        (story === msg % tail)

  end

module MemStory =
  struct
    type tt = (Loc.tt, LocStory.tt) VarList.tt
    type tl = (Loc.tl, LocStory.tl) VarList.tl
    type ti = (Loc.tt, LocStory.tt, Loc.tl, LocStory.tl) VarList.ti

    let inj = List.inj (fun (loc, story) -> inj_pair (!!loc) (LocStory.inj story))

    let to_logic = List.to_logic (fun (var, story) -> Value (Value var, LocStory.to_logic story))

    let reify h = ManualReifiers.(List.reify (pair (string) (LocStory.reify)) h)

    let create = List.of_list (fun x -> x)

    let preallocate atomics = List.of_list (fun loc -> (loc, LocStory.preallocate atomics)) atomics

    let printer ff story =
      let pp ff (var, story) = LocStory.printer var ff story in
      Format.fprintf ff "@[<v>Memory :@;<1 4>%a@;@]" (pprint_llist (pprint_logic pp)) story

    let pprint story =
      printer Format.str_formatter story;
      Format.flush_str_formatter ()

    let last_tso t loc ts =
      fresh (story)
        (VarList.geto t loc story)
        (LocStory.last_tso story ts)

    let next_tso t loc ts =
      fresh (story)
        (VarList.geto t loc story)
        (LocStory.next_tso story ts)

    let reado t loc last_ts ts value vf =
      fresh (story)
        (VarList.geto t loc story)
        (LocStory.reado story last_ts ts value vf)

    let writeo t t' loc value vf  =
      fresh (story story')
        (VarList.geto t loc story)
        (VarList.seto t t' loc story')
        (LocStory.writeo story story' value vf)

    let last_valueo t loc value =
      fresh (story story)
        (VarList.geto t loc story)
        (LocStory.last_valueo story value)

  end

module MemState =
  struct
    module T = struct
      type ('a, 'b, 'c, 'd) t = {
        thrds : 'a;
        story : 'b;
        na    : 'c;
        sc    : 'd;
      }

      let fmap fa fb fc fd {thrds; story; na; sc} = {
        thrds = fa thrds;
        story = fb story;
        na = fc na;
        sc = fd sc;
      }

    end

    type tt = (Threads.tt, MemStory.tt, ViewFront.tt, ViewFront.tt) T.t
    type tl_inner = (Threads.tl, MemStory.tl, ViewFront.tl, ViewFront.tl) T.t
    type tl = tl_inner logic
    type ti = (tt, tl) MiniKanren.injected

    include Fmap4(T)

    let mem_state thrds story na sc = inj @@ distrib @@ T.({thrds; story; na; sc;})

    let inj {T.thrds = thrds; T.story = story; T.na = na; T.sc = sc;} =
      mem_state (Threads.inj thrds) (MemStory.inj story) (ViewFront.inj na) (ViewFront.inj sc)

    let to_logic {T.thrds = thrds; T.story = story; T.na = na; T.sc = sc} =
      Value {
        T.thrds = Threads.to_logic thrds;
        T.story = MemStory.to_logic story;
        T.na    = ViewFront.to_logic na;
        T.sc    = ViewFront.to_logic sc;
      }

    let refine rr = rr#refine (reify Threads.reify MemStory.reify ViewFront.reify ViewFront.reify) ~inj:to_logic

    let create ?(na=ViewFront.from_list []) ?(sc=ViewFront.from_list []) thrds story = {
      T.thrds = thrds;
      T.story = story;
      T.na    = na;
      T.sc    = sc;
    }

    let preallocate vars atomics =
      let thrd  = ThreadState.preallocate vars atomics in
      let thrds = Threads.Tree.Node (thrd, Threads.Tree.Nil, Threads.Tree.Nil) in
      let story = MemStory.preallocate atomics in
      let na    = ViewFront.allocate atomics in
      let sc    = ViewFront.allocate atomics in
      create thrds story ~na ~sc

    let printer =
      let pp ff {T.thrds = thrds; T.story = story; T.na = na; T.sc = sc;} =
        Format.fprintf ff "@[<v>%a@;%a@;@[<v>NA-front :@;<1 4>%a@;@]@;@[<v>SC-front :@;<1 4>%a@;@]@]"
          Threads.printer thrds
          MemStory.printer story
          ViewFront.printer na
          ViewFront.printer sc
      in
      pprint_logic pp

    let pprint story =
      printer Format.str_formatter story;
      Format.flush_str_formatter ()

    let get_thrdo t path thrd =
      fresh (tree story na sc)
        (t === mem_state tree story na sc)
        (Threads.geto tree path thrd)

    let set_thrdo t t' path thrd =
      fresh (tree tree' story na sc)
        (t  === mem_state tree  story na sc)
        (t' === mem_state tree' story na sc)
        (Threads.seto tree tree' path thrd)

    let get_localo t path var value =
      fresh (thrd)
        (get_thrdo t path thrd)
        (ThreadState.get_varo thrd var value)

    let set_localo t t' path var value =
      fresh (thrd thrd')
        (get_thrdo t path thrd)
        (set_thrdo t t' path thrd')
        (ThreadState.set_varo thrd thrd' var value)

    let na_awareo na thrd loc = Nat.(
      fresh (ts write_ts)
        (ThreadState.tso thrd loc ts)
        (VarList.geto na loc write_ts)
        (write_ts <= ts)
    )

    let read_nao t t' path loc value ts = Nat.(
      fresh (tree story na sc thrd vf)
        (t === t')
        (t === mem_state tree story na sc)
        (Threads.geto tree path thrd)
        (ThreadState.tso thrd loc ts)
        (MemStory.last_tso story loc ts)
        (na_awareo na thrd loc)
        (MemStory.reado story loc ts ts value vf)
    )

    let write_nao t t' path loc value ts' = Nat.(
      fresh (tree tree' story story' na na' sc thrd thrd' ts rel vf)
        (t  === mem_state tree  story  na  sc)
        (t' === mem_state tree' story' na' sc)
        (Threads.geto tree       path thrd)
        (Threads.seto tree tree' path thrd')
        (ThreadState.tso thrd loc ts)
        (MemStory.last_tso story loc ts)
        (na_awareo na thrd loc)

        (MemStory.next_tso story loc ts')
        (ThreadState.updateo thrd thrd' loc ts')
        (ViewFront.updateo na na' loc ts')

        (ThreadState.front_relo thrd' loc rel)
        (ViewFront.reseto rel vf)
        (MemStory.writeo story story' loc value vf)
    )

    let na_stucko t path loc =
      fresh (tree story na sc thrd ts last_ts)
        (t === mem_state tree story na sc)
        (Threads.geto tree path thrd)
        (ThreadState.tso thrd loc ts)
        (MemStory.last_tso story loc last_ts)
        (ts =/= last_ts)

    let read_na_dro t t' path loc =
      (t === t') &&&
      (na_stucko t path loc)

    let write_na_dro t t' path loc =
      (t === t') &&&
      (na_stucko t path loc)

    let data_raceo t path loc = Nat.(
      fresh (tree story na sc thrd ts write_ts)
        (t === mem_state tree story na sc)
        (Threads.geto tree path thrd)
        (ThreadState.tso thrd loc ts)
        (VarList.geto na loc write_ts)
        (ts < write_ts)
    )

    let read_dro t t' path loc =
      (t === t') &&&
      (data_raceo t path loc)

    let write_dro t t' path loc =
      (t === t') &&&
      (data_raceo t path loc)

    let read_rlxo t t' path loc value ts =
      fresh (tree tree' story story' na sc thrd thrd' thrd'' last_ts vf)
        (t  === mem_state tree  story na sc)
        (t' === mem_state tree' story na sc)
        (Threads.geto tree       path thrd)
        (Threads.seto tree tree' path thrd'')
        (na_awareo na thrd loc)
        (ThreadState.tso thrd loc last_ts)
        (MemStory.reado story loc last_ts ts value vf)
        (ThreadState.update_acqo thrd thrd' vf)
        (ThreadState.updateo thrd' thrd'' loc ts)

    let write_rlxo t t' path loc value ts =
      fresh (tree tree' story story' na sc thrd thrd' rel)
        (t  === mem_state tree  story  na sc)
        (t' === mem_state tree' story' na sc)
        (Threads.geto tree       path thrd)
        (Threads.seto tree tree' path thrd')
        (na_awareo na thrd loc)
        (MemStory.next_tso story loc ts)
        (ThreadState.front_relo thrd loc rel)
        (ThreadState.updateo thrd thrd' loc ts)
        (MemStory.writeo story story' loc value rel)

    let fence_acqo t t' path =
      fresh (tree tree' story thrd thrd' na sc)
        (t  === mem_state  tree  story na sc)
        (t' === mem_state  tree' story na sc)
        (Threads.geto tree       path thrd )
        (Threads.seto tree tree' path thrd')
        (ThreadState.fence_acqo  thrd thrd')

    let fence_relo t t' path =
      fresh (tree tree' story na sc thrd thrd')
        (t  === mem_state  tree  story na sc)
        (t' === mem_state  tree' story na sc)
        (Threads.geto tree       path thrd )
        (Threads.seto tree tree' path thrd')
        (ThreadState.fence_relo  thrd thrd')

    let fence_loc_relo t t' path loc =
      fresh (tree tree' story na sc thrd thrd')
        (t  === mem_state  tree  story na sc)
        (t' === mem_state  tree' story na sc)
        (Threads.geto tree       path thrd )
        (Threads.seto tree tree' path thrd')
        (ThreadState.fence_loc_relo thrd thrd' loc)

    let read_acqo t t'' path loc value ts =
      fresh (t')
        (read_rlxo t t' path loc value ts)
        (fence_acqo t' t'' path)

    let write_relo t t'' path loc value ts =
      fresh (t')
        (fence_loc_relo t t' path loc)
        (write_rlxo t' t'' path loc value ts)

    let read_sco t t' path loc value ts = Nat.(
      fresh (tree story na sc sc_ts ts)
        (t === mem_state tree story na sc)
        (read_acqo t t' path loc value ts)
        (VarList.geto sc loc sc_ts)
        (sc_ts <= ts)
    )

    let write_sco t t'' path loc value ts =
      fresh (t' tree story na sc sc' ts)
        (t'   === mem_state tree story na sc )
        (t''  === mem_state tree story na sc')
        (write_relo t t' path loc value ts)
        (ViewFront.updateo sc sc' loc ts)

    let last_valueo t loc value =
      fresh (tree tree story na sc)
        (t  === mem_state tree story na sc)
        (MemStory.last_valueo story loc value)

    let promiseo t t' path loc value =
      fresh (tree tree' story story' na sc thrd thrd' ts rel)
        (t  === mem_state  tree  story  na sc)
        (t' === mem_state  tree' story' na sc)
        (Threads.geto tree       path thrd )
        (Threads.seto tree tree' path thrd')
        (MemStory.next_tso story loc ts)
        (ThreadState.front_relo thrd loc rel)
        (ThreadState.promiseo thrd thrd' loc ts value rel)
        (MemStory.writeo story story' loc value rel)

    let fulfillo t t' path =
      fresh (tree tree' story na sc thrd thrd' ts)
        (t  === mem_state  tree  story na sc)
        (t' === mem_state  tree' story na sc)
        (Threads.geto tree       path thrd )
        (Threads.seto tree tree' path thrd')
        (ThreadState.fulfillo thrd thrd')

    let laggingo t b =
      fresh (tree story na sc)
        (t === mem_state tree story na sc)
        (Threads.laggingo tree b)

    let certifyo t path =
      fresh (tree story na sc thrd)
        (t  === mem_state tree story na sc)
        (Threads.geto tree path thrd)
        (ThreadState.certifyo thrd)

    let spawno t t' path =
      fresh (tree tree' story na sc)
        (t  === mem_state tree  story na sc)
        (t' === mem_state tree' story na sc)
        (Threads.spawno tree tree' path)

    let joino t t' path =
      fresh (tree tree' story na sc)
        (t  === mem_state tree  story na sc)
        (t' === mem_state tree' story na sc)
        (Threads.joino tree tree' path)
  end
