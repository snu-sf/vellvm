Add LoadPath "../../ssa/ott".
Add LoadPath "../../ssa/monads".
Add LoadPath "../../ssa/compcert".
Add LoadPath "../../ssa".
Add LoadPath "../../../../theory/metatheory_8.3".
Add LoadPath "../../TV".
Require Import sb_db_def.
Require Import Metatheory.

Ltac invert_prop_reg_metadata :=
  match goal with
  | [H : SoftBound.prop_reg_metadata _ _ _ _ _ = (_, _) |- _ ] =>
      inversion H; subst; eauto
  end.

Ltac invert_result :=
  match goal with
  | [H : SoftBound.is_error SoftBound.rok |- _ ] => inversion H
  | [H : SoftBound.rerror = SoftBound.rok |- _ ] => inversion H
  | [H : SoftBound.rabort = SoftBound.rok |- _ ] => inversion H 
  | [H : SoftBound.rok = SoftBound.rerror |- _ ] => inversion H 
  | [H : SoftBound.rok = SoftBound.rabort |- _ ] => inversion H 
 end.

Ltac SSSSSCase name := Case_aux subsubsubsubsubcase name.
Ltac SSSSSSCase name := Case_aux subsubsubsubsubsubcase name.
Ltac SSSSSSSCase name := Case_aux subsubsubsubsubsubsubcase name.

Ltac zauto := auto with zarith.
Ltac zeauto := eauto with zarith.

(*****************************)
(*
*** Local Variables: ***
*** coq-prog-name: "coqtop" ***
*** coq-prog-args: ("-emacs-U" "-I" "~/SVN/sol/vol/src/ssa/monads" "-I" "~/SVN/sol/vol/src/ssa/ott" "-I" "~/SVN/sol/vol/src/ssa/compcert" "-I" "~/SVN/sol/theory/metatheory_8.3" "-I" "~/SVN/sol/vol/src/TV") ***
*** End: ***
 *)
