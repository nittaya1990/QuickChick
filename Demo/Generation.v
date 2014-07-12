Require Import QuickChick.

Require Import ZArith.
Require Import NPeano.
Require Import List.
Import ListNotations.
Require Import Machine.

(* Overriding default instance to generate "in-bounds" things *)
Definition gen_int := chooseZ (0,1).

Definition gen_label := elements L [L; H].

Definition gen_atom := liftGen2 Atm gen_int gen_label.

Definition gen_memory := vectorOf 2 gen_atom.

Local Open Scope nat.
Definition ainstr (st : State) : Gen Instruction :=
  let '(St im m stk pc ) := st in
  let fix stack_length s := 
      match s with 
        | _ :: s' => 1 + stack_length s'
        | _ => 0
      end in
  let sl := stack_length stk in
  let fix containsRet s := 
      match s with
        | _ ::: _ => true
        | _ :: s' => containsRet s'
        | _ => false
      end in
  let onLength len x := if ltb x len then x else 0 in
  frequency (returnGen Nop) [
              (1, returnGen Nop);
              (10, liftGen Push gen_int);
              (onLength 1 10, liftGen BCall (chooseZ (0, (Z.of_nat sl-1))%Z));
              (if containsRet stk then 10 else 0, returnGen BRet);
              (onLength 2 10, returnGen Add);
              (onLength 1 10, returnGen Load);
              (onLength 2 10, returnGen Store)].

Fixpoint gen_stack (n : nat) (onlyHigh : bool) : Gen Stack :=
  let gen_atom := 
      if onlyHigh then liftGen2 Atm gen_int (returnGen H)
      else gen_atom
  in
  match n with
    | O => returnGen Mty
    | S n' => 
      frequency (returnGen Mty) [
                  (10, liftGen2 Cons gen_atom (gen_stack n' onlyHigh));
                  (10, bindGen gen_atom (fun pc =>
                       let onlyHigh := 
                           match pc with
                             | _ @ L => false
                             | _ @ H => true
                           end in
                       liftGen (RetCons pc) (gen_stack n' onlyHigh)))]
  end.

Definition gen_state : Gen State :=
  let imem0 := [Nop; Nop] in
  bindGen gen_atom (fun pc =>
  bindGen gen_memory (fun mem =>
  bindGen (gen_stack 4 false) (fun stk =>
  bindGen (ainstr (St imem0 mem stk pc)) (fun i =>
  returnGen (St [i;i] mem stk pc))))).                                              

(* State Variations *)
Inductive Variation {A : Type} := V : A -> A -> @Variation A.

Class Vary (A : Type) := {
  vary : A -> Gen A
}.

Instance vary_atom : Vary Atom := 
{|
  vary a := 
    let '(x @ l) := a in
    match l with
      | L => returnGen a
      | H => gen_atom 
    end
|}.

Instance vary_mem : Vary Mem :=
{|
  vary m := sequenceGen (map vary m)
|}.

Fixpoint vary_stack (s : Stack) (isLow : bool) : Gen Stack :=
  match s with
    | a :: s'  => if isLow then liftGen2 Cons (vary a) (vary_stack s' isLow)
                  else liftGen2 Cons gen_atom (vary_stack s' isLow)
    | (x@l) ::: s' => 
      match l with
        | L => liftGen (RetCons (x@l)) (vary_stack s' true)
        | H => liftGen2 RetCons (vary (x@l)) (vary_stack s' false)
      end
    | Mty => returnGen Mty
  end.

Instance vary_state : Vary State :=
{|
  vary st :=
    let '(St imem mem stk pc) := st in
    bindGen (vary mem) (fun mem' =>
    bindGen (vary pc)  (fun pc' => 
    let isLow := match pc with
                   | _ @ L => true
                   | _ @ H => false
                 end in
    if isLow then 
      bindGen (vary_stack stk isLow) (fun stk' =>
      returnGen (St imem mem' stk' pc'))
    else
      bindGen (vary_stack stk isLow) (fun stk' =>
      bindGen gen_atom (fun extra_elem =>
      returnGen (St imem mem' (extra_elem :: stk') pc')))))
|}.                          

Definition gen_variation_state : Gen (@Variation State) :=
  bindGen gen_state (fun st =>
  bindGen (vary st) (fun st' =>
  returnGen (V st st'))).