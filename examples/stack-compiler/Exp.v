Set Warnings "-extraction-opaque-accessed,-extraction".
Set Warnings "-notation-overridden,-parsing".

From QuickChick Require Import QuickChick.

(** * Arithmetic Expressions *)

(** The code in the [stack-compiler] subdirectory consists of two
    modules, [Exp] and [Stack], each containing a number of
    definitions and properties. After some [Import]s at the top,
    it defines a little arithmetic language, consisting of
    natural literals, addition, subtraction and multiplication. *)

Inductive exp : Type :=
  | ANum : nat -> exp
  | APlus : exp -> exp -> exp
  | AMinus : exp -> exp -> exp
  | AMult : exp -> exp -> exp.

Derive Show for exp.
(* Print Showexp.*)
(*
Showexp = 
{|
show := fun x : exp =>
        let
          fix aux (x' : exp) : String.string :=
            match x' with
            | ANum p0 => String.append "ANum " (smart_paren (show p0))
            | APlus p0 p1 =>
                String.append "APlus "
                  (String.append (smart_paren (aux p0))
                     (String.append " " (smart_paren (aux p1))))
            | AMinus p0 p1 =>
                String.append "AMinus "
                  (String.append (smart_paren (aux p0))
                     (String.append " " (smart_paren (aux p1))))
            | AMult p0 p1 =>
                String.append "AMult "
                  (String.append (smart_paren (aux p0))
                     (String.append " " (smart_paren (aux p1))))
            end in
        aux x |}
     : Show exp
 *)






Instance Shrink_exp_bad : Shrink exp | 100 :=
  {| shrink := fun _ => nil |}.


























(* We can also derive a generator for expressions. *)
Derive GenSized for exp.

(* Sample (@arbitrary exp _). *)


(* Let's define an evaluation function... *)
Fixpoint eval (e : exp) : nat :=
  match e with
  | ANum n => n
(*! *)                
  | APlus e1 e2 => (eval e1) + (eval e2)
(*!! Plus-copy-paste-error *)                                 
(*! | APlus e1 e2 => (eval e1) + (eval e1) *)
  | AMinus e1 e2  => (eval e1) - (eval e2)
  | AMult e1 e2 => (eval e1) * (eval e2)
  end.

(* ...and perform a few optimizations: *)
Fixpoint optimize (e : exp) : exp :=
  match e with
  | ANum n => ANum n
  | APlus e (ANum 0)  => optimize e
  | APlus (ANum 0) e  => optimize e
  | APlus e1 e2 => APlus (optimize e1) (optimize e2)
(*! *)
  | AMinus e (ANum 0) => optimize e 
(*!! Minus-Reverse *)
(*!
  | AMinus (ANum 0) e => optimize e 
*)
  | AMinus e1 e2 => AMinus (optimize e1) (optimize e2)
  | AMult e1 e2 => AMult (optimize e1) (optimize e2)
  end.

(* We would expect that optimizations don't affect the evaluation result. *)
Definition optimize_correct_prop (e : exp) := eval (optimize e) = eval e?.

(* Does that hold? *)
(*! QuickChick optimize_correct_prop. *)

Derive Shrink for exp.

QuickChick optimize_correct_prop.