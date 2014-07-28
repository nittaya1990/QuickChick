Require Import AbstractGen Property SetOfOutcomes.

Definition semProperty (P : Pred QProp) : Prop :=
  forall qp, P qp -> failure qp = false.

Definition semTestable {A : Type} {_ : @Testable Pred A} (a : A) : Prop :=
  semProperty (property a).


