(* Start CoqIDE at ./src/TV *)
Add LoadPath "../ssa/ott".
Add LoadPath "../ssa/monads".
Add LoadPath "../ssa/compcert".
Add LoadPath "../ssa".
Add LoadPath "../../../theory/metatheory_8.3".
Require Import ssa_def.
Require Import ssa_lib.
Require Import List.
Require Import targetdata.
Require Import monad.
Require Import Arith.
Require Import Metatheory.
Require Import ssa_mem.
Require Import genericvalues.
Require Import ssa_dynamic.
Require Import trace.
Require Import assoclist.
Require Import ssa_props.
Require Import CoqListFacts.
Require Import symexe_def.
Require Import symexe_lib.
Require Import eq_tv_dec.

Export SimpleSE.

Lemma typ_sterm_dec : forall (st1 st2:typ*sterm), {st1=st2}+{~st1=st2}.
Proof.
  destruct st1 as (t1,s1).
  destruct st2 as (t2,s2).
  destruct (@typ_dec t1 t2); subst; try solve [done_right].
  destruct (@sterm_dec s1 s2); subst; try solve [auto | done_right].
Qed.

Definition sub_sstate s1 s2 := 
  s1.(STerms) <<<= s2.(STerms) /\ s1.(SMem) = s2.(SMem) /\
  s1.(SFrame) = s2.(SFrame) /\ s1.(SEffects) = s2.(SEffects).

Notation "s1 <<= s2" := (sub_sstate s1 s2) (at level 70, no associativity).

Lemma smap_sub_dec : forall (sm1 sm2:smap), 
  uniq sm1 -> {sm1 <<<= sm2}+{~sm1 <<<= sm2}.
Proof.
  induction sm1.  
    intros. left. intros i i_in_nil. fsetdec. 

    intros sm2 Huniq. 
    destruct a as [id st1].
    remember (lookupAL _ sm2 id) as Lookup.
    destruct Lookup as [st2 | _].
      destruct (@sterm_dec st1 st2); subst.
        destruct_uniq.
        destruct (@IHsm1 sm2 Huniq) as [sm1_sub_sm2 | sm1_nsub_sm2].
          left. simpl_env.
          apply subAL_app1; auto.
            intros i Hi_in_dom. simpl in *.
            destruct (@eq_dec atom (EqDec_eq_of_EqDec atom EqDec_atom) i id); 
              subst.
              rewrite <- HeqLookup; auto.
              fsetdec.

          right. simpl_env.
          apply subAL_app2; auto.
            intros id0 Hid0_in.
            assert (id0=id) as Eq. simpl in Hid0_in. fsetdec.
            subst.
            simpl. 
            destruct (@eq_dec atom (EqDec_eq_of_EqDec atom EqDec_atom) id id); 
              auto.
              contradict n; auto.
        right. intro J. assert (H:=@J id). simpl in H.
        destruct (@eq_dec atom (EqDec_eq_of_EqDec atom EqDec_atom) id id); auto.
          rewrite <- HeqLookup in H. injection H; auto.
      right. intro J. assert (H:=@J id). simpl in H.
      destruct (@eq_dec atom (EqDec_eq_of_EqDec atom EqDec_atom) id id); auto.
        rewrite <- HeqLookup in H.
        assert (ret st1 = merror) as F. auto.
        inversion F.
Qed.

Lemma sstate_sub_dec : forall (sts1 sts2:sstate), 
  uniq sts1.(STerms) -> {sts1<<=sts2} + {~sts1<<=sts2}.
Proof.
Ltac done_right' := 
  right; intro J ; destruct J as [ J1 [J2 [J3 J4]]]; simpl in *; auto.

  intros sts1 sts2 Huniq.
  destruct sts1 as [st1 sm1 sf1 se1].
  destruct sts2 as [st2 sm2 sf2 se2].
  destruct (@sterms_dec se1 se2); subst; try solve [auto | done_right'].
  destruct (@sframe_dec sf1 sf2); subst; try solve [auto | done_right'].
  destruct (@smem_dec sm1 sm2); subst; try solve [auto | done_right'].
  destruct (@smap_sub_dec st1 st2 Huniq); subst; 
    try solve [left; split; auto | done_right'].
Qed.

Definition prefix A (l1 l:list A) := exists l2, l1 ++ l2 = l.

(* A more general way is to check if l1 is a subset of l2. By doing that way,
 * at call-site, we also need to ensure parameters are matched. The prefix
 * checking is sufficient to Softbound.
*)
Lemma prefix_dec : forall A, (forall (a1 a2:A), {a1=a2}+{~a1=a2}) ->
  forall (l1 l2:list A), {prefix _ l1 l2}+{~prefix _ l1 l2}.
Proof.
  induction l1.
    left. exists l2. auto.

    destruct l2.
      right. intro J. destruct J as [l EQ].
      inversion EQ.

      destruct (@X a a0); subst.
        destruct (@IHl1 l2).
          left. destruct p as [l EQ]; subst.
          exists l. auto.

          right. intro J. apply n.
          destruct J as [l EQ].
          inversion EQ; subst.
          exists l. auto.
        right. intro J. destruct J as [l EQ].        
        inversion EQ; subst; auto.
Qed.

(*****************************)
(*
*** Local Variables: ***
*** coq-prog-name: "coqtop" ***
*** coq-prog-args: ("-emacs-U" "-I" "~/SVN/sol/vol/src/ssa/monads" "-I" "~/SVN/sol/vol/src/ssa/ott" "-I" "~/SVN/sol/vol/src/ssa/compcert" "-I" "~/SVN/sol/theory/metatheory_8.3") ***
*** End: ***
 *)