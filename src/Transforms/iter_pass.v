Require Import vellvm.
Require Import Iteration.

(* Define an iterated block-level transformation pass. *)

(* One iteration:
   effects: the states that a pass needs to maintain;
   context: unchanged parameters of the pass;
   iter_block: the transformer that, given a function, a block in the function,
     parameters and states, returns whether the function is changed, and the 
     changed function and states.
   init_effects: initial states. *)
Structure IterPass := mkIterPass {
  effects: Type;
  context: Type;
  iter_block : fdef -> block -> context -> effects -> fdef * bool * effects;
  init_effects: effects
}.

Module IterationPass.

Section IterationPass. 

Variable (pass:IterPass).

(* Apply iter_block to a list of blocks *)
Fixpoint iter_blocks (f:fdef) (bs: blocks) (ctx:pass.(context)) (rd:list l) 
  (efs:pass.(effects)) : fdef * bool * pass.(effects) :=
match bs with
| nil => (f, false, efs)
| b::bs' =>
    if (in_dec id_dec (getBlockLabel b) rd) then
      let '(f', changed, efs') := pass.(iter_block) f b ctx efs in
      if changed then (f', true, efs') 
      else iter_blocks f' bs' ctx rd efs'
    else iter_blocks f bs' ctx rd efs
end.

(* Apply iter_block to a function *)
Definition iter_fdef (f:fdef) (ctx:pass.(context)) (rd:list l)  
  (efs:pass.(effects)) : fdef * bool * pass.(effects) :=
let '(fdef_intro fh bs) := f in iter_blocks f bs ctx rd efs.

(* The iteration runs until the maximal number of steps reaches, or 
   the function is not changed. *)
Definition iter_step (ctx:pass.(context)) (rd:list l) (st: fdef * pass.(effects))
  : fdef * pass.(effects) + fdef * pass.(effects) :=
let '(f, efs) := st in
let '(f1, changed1, efs1) := iter_fdef f ctx rd efs in
if changed1 then inr _ (f1, efs1) else inl _ (f1, efs1).

Definition iter (ctx:pass.(context)) (rd:list l) (f:fdef) 
  : fdef * pass.(effects) := 
SafePrimIter.iterate _ (iter_step ctx rd) (f, pass.(init_effects)).

End IterationPass.
End IterationPass.

