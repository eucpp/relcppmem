open MiniKanren
open MiniKanrenStd
open OUnit2
open Lang
open Memory

module T = Lang.Term.T
module C = Lang.Context.T
module S = MemState

let parse str =
  let lexbuf = Lexing.from_string str in
  Parser.parse Lexer.token lexbuf

let test_parse str expected test_ctx =
  let actual = Term.from_logic @@ parse str in
  assert_equal expected actual ~printer:(fun t -> Term.pprint @@ Term.to_logic t)

let test_parse_logic str expected test_ctx =
  let actual = parse str in
  assert_equal expected actual ~printer:Term.pprint

let const n = T.Const (Nat.of_int n)

let parser_tests =
  "expr">::: [
    "test_const">:: test_parse "ret 1" (const 1);
    "test_var">:: test_parse "ret r1" (T.Var "r1");
    "test_binop">:: test_parse "ret 1+r1" (T.Binop ("+", const 1, T.Var "r1"));

    "test_asgn">:: test_parse "r1 := 0" (T.Asgn (T.Var "r1", const 0));
    "test_if">:: test_parse "if 1 then skip else stuck fi" (T.If (const 1, T.Skip, T.Stuck));

    "test_repeat">:: test_parse "repeat 1 end" (T.Repeat (const 1));

    "test_read">:: test_parse "ret x_acq" (T.Read (MemOrder.ACQ, "x"));
    "test_write">:: test_parse "x_rel := 1" (T.Write (MemOrder.REL, "x", const 1));

    "test_seq">:: test_parse "skip; stuck" (T.Seq (T.Skip, T.Stuck));
    "test_spw">:: test_parse "spw {{{ skip ||| stuck }}}" (T.Spw (T.Skip, T.Stuck));

    "test_partial">:: (
        test_parse_logic "?1; ret r1" (Value (T.Seq (Var (1, []), Value (T.Var (Value "r1")))))
      )
  ]

let tests =
  "parser">::: [parser_tests; ]
