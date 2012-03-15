Require Import vellvm.

Module MemProps.

(* wf_global and wf_globals are copied from sb_ds_gv_inject.v
   We should move the invariant to memory model. *)
Fixpoint wf_global (maxb:Values.block) (gv:GenericValue)
  : Prop :=
match gv with
| nil => True
| (Vptr b _,_)::gv' => b <= maxb /\ wf_global maxb gv'
| _::gv' => wf_global maxb gv'
end.

Fixpoint wf_global_list maxb (gl:GVMap) : Prop :=
match gl with
| nil => True
| (_,gv)::gl' => wf_global maxb gv /\ wf_global_list maxb gl'
end.

Definition wf_globals maxb (gl:GVMap) : Prop :=
0 <= maxb /\ wf_global_list maxb gl.

Fixpoint no_alias_with_blk (gvs:GenericValue) (blk:Values.block) : Prop :=
match gvs with
| nil => True
| (Vptr b _,_)::gvs' => b <> blk /\ no_alias_with_blk gvs' blk
| _::gvs' => no_alias_with_blk gvs' blk
end.

Fixpoint no_alias (gvs1 gvs2:GenericValue) : Prop :=
match gvs2 with
| nil => True
| (Vptr b _,_)::gvs2' => no_alias_with_blk gvs1 b /\ no_alias gvs1 gvs2'
| _::gvs2' => no_alias gvs1 gvs2'
end.

Fixpoint valid_ptrs (bound:Values.block) (gvs:GenericValue): Prop :=
match gvs with
| nil => True
| (Vptr blk _,_)::gvs' => blk < bound /\ valid_ptrs bound gvs'
| _::gvs' => valid_ptrs bound gvs'
end.

Definition wf_lc M lc : Prop :=
forall id0 gvs,
  lookupAL _ lc id0 = Some gvs -> valid_ptrs (Mem.nextblock M) gvs.

Definition wf_Mem maxb (td:targetdata) (M:mem) : Prop :=
(forall gptr ty al gvs,
  mload td M gptr ty al = Some gvs -> valid_ptrs (Mem.nextblock M) gvs) /\
maxb < Mem.nextblock M.

Definition wf_als maxb M (als: list Values.block) : Prop :=
NoDup als /\ (forall al, In al als -> maxb < al < Mem.nextblock M).

Lemma no_alias_with_blk_dec: forall blk gvs,
  no_alias_with_blk gvs blk \/ ~ no_alias_with_blk gvs blk.
Proof.
  induction gvs as [|[[]]]; simpl; auto.
    destruct (Z_eq_dec b blk); subst.
      right. intros [J1 J2]. auto.

      destruct IHgvs; auto.
        right. intros [J1 J2]. auto.
Qed.

Lemma null_valid_ptrs: forall mb, mb > 0 -> valid_ptrs mb null.
Proof.
  intros. unfold null, Mem.nullptr. simpl.
  split; auto. omega.
Qed.

Lemma uninits_valid_ptrs: forall bd n, valid_ptrs bd (uninits n).
Proof.
  intros.
  induction n; simpl; auto.
Qed.

Fixpoint no_embedded_ptrs (gvs:GenericValue): Prop :=
match gvs with
| nil => True
| (Vptr _ _,_)::gvs' => False
| _::gvs' => no_embedded_ptrs gvs'
end.

Lemma no_alias_with_blk__mc2undefs : forall l1 mb,
  no_alias_with_blk (mc2undefs l1) mb.
Proof. induction l1; simpl; auto. Qed.

Lemma no_embedded_ptrs__no_alias_with_blk: forall b2 gvs1,
  no_embedded_ptrs gvs1 -> no_alias_with_blk gvs1 b2.
Proof.
  induction gvs1 as [|[]]; simpl; intros; auto.
    destruct v; auto. inv H.
Qed.

Lemma mc2undefs__no_embedded_ptrs: forall l0, 
  no_embedded_ptrs (mc2undefs l0).
Proof.
  induction l0; simpl; auto.
Qed.

Lemma undef__no_embedded_ptrs: forall g td t1
  (Hc2g : ret g = gundef td t1), no_embedded_ptrs g.
Proof.
  unfold gundef. intros.
  inv_mbind'. simpl. apply mc2undefs__no_embedded_ptrs.
Qed.

Lemma no_embedded_ptrs__no_alias: forall gvs1 gvs2,
  no_embedded_ptrs gvs1 -> no_alias gvs1 gvs2.
Proof.
  induction gvs2 as [|[]]; simpl; intros; auto.
    destruct v; auto.
    split; auto using no_embedded_ptrs__no_alias_with_blk.
Qed.

Lemma undef_disjoint_with_ptr: forall g td t1 g'
  (Hc2g : ret g = gundef td t1), no_alias g g'.
Proof.
  intros. apply undef__no_embedded_ptrs in Hc2g.
  apply no_embedded_ptrs__no_alias; auto.
Qed.

Lemma no_alias_with_blk_app: forall g2 b g1,
  no_alias_with_blk g1 b -> no_alias_with_blk g2 b ->
  no_alias_with_blk (g1++g2) b.
Proof.
  induction g1; simpl; intros; auto.
    destruct a.
    destruct v; auto.
    destruct H; auto.
Qed.

Lemma no_alias_app: forall g2 g1 g,
  no_alias g1 g -> no_alias g2 g -> no_alias (g1++g2) g.
Proof.
  induction g; simpl; intros; auto.
    destruct a.
    destruct v; auto.
    destruct H. destruct H0.
    split; auto using no_alias_with_blk_app.
Qed.

Lemma no_alias_nil: forall g, no_alias nil g.
Proof.
  induction g; simpl; intros; auto.
    destruct a.
    destruct v; auto.
Qed.

Lemma no_alias_dec: forall gvs1 gvs2,
  no_alias gvs1 gvs2 \/ ~ no_alias gvs1 gvs2.
Proof.
  induction gvs2 as [|[]]; destruct gvs1 as [|[]]; simpl; auto.
    destruct v; try solve [left; auto using no_alias_nil].

    destruct v; simpl; auto.
    destruct v0; simpl; try
      destruct (@no_alias_with_blk_dec b gvs1); try solve [
        destruct IHgvs2; try solve [auto | right; intros [J1 J2]; auto];
        right; intros [J1 J2]; auto
      ].

      destruct (Z_eq_dec b0 b); subst.
        tauto.
        destruct IHgvs2; tauto.
      tauto.
Qed.

Lemma no_alias_repeatGV: forall g1 g2 n,
  no_alias g1 g2 -> no_alias (repeatGV g1 n) g2.
Proof.
  induction n; simpl; intros.
    apply no_alias_nil.
    apply no_alias_app; auto.
Qed.

Lemma valid_ptrs_app: forall bd g2 g1,
  valid_ptrs bd g1 -> valid_ptrs bd g2 -> valid_ptrs bd (g1++g2).
Proof.
  induction g1 as [|[]]; simpl; intros; auto.
    destruct v; auto.
    destruct H.
    split; auto.
Qed.

Lemma valid_ptrs_repeatGV: forall n bd g,
  valid_ptrs bd g -> valid_ptrs bd (repeatGV g n).
Proof.
  induction n; simpl; intros; auto.
    apply valid_ptrs_app; auto.
Qed.

Lemma no_embedded_ptrs__valid_ptrs: forall bd gvs,
  no_embedded_ptrs gvs -> valid_ptrs bd gvs.
Proof.
  induction gvs as [|[]]; simpl; intros; auto.
    destruct v; auto.
      inversion H.
Qed.

Lemma mtrunc_preserves_no_embedded_ptrs: forall td top t1 t2 gv gv',
  mtrunc td top t1 t2 gv = Some gv' -> no_embedded_ptrs gv'.
Proof.
  intros.
  unfold mtrunc in H.
  remember (GV2val td gv) as R.
  destruct R; eauto using undef__no_embedded_ptrs.
  destruct v; eauto using undef__no_embedded_ptrs.
    destruct_typ t1; eauto using undef__no_embedded_ptrs.
      destruct_typ t2; eauto using undef__no_embedded_ptrs.
        inv H. destruct (le_lt_dec wz s1); simpl; auto.

    destruct_typ t1; eauto using undef__no_embedded_ptrs.
      destruct_typ t2; eauto using undef__no_embedded_ptrs.
      destruct (floating_point_order f1 f0); tinv H.
      destruct f1; inv H; unfold val2GV; simpl; auto.
Qed.

Lemma mtrunc_preserves_no_alias: forall td top t1 t2 gv gv' gv0,
  mtrunc td top t1 t2 gv = Some gv' -> no_alias gv' gv0.
Proof.
  intros.
  apply no_embedded_ptrs__no_alias.
  apply mtrunc_preserves_no_embedded_ptrs in H; auto.
Qed.

Lemma mtrunc_preserves_valid_ptrs: forall td top t1 t2 gv gv' bd,
  mtrunc td top t1 t2 gv = Some gv' -> valid_ptrs bd gv'.
Proof.
  intros.
  apply no_embedded_ptrs__valid_ptrs.
  apply mtrunc_preserves_no_embedded_ptrs in H; auto.
Qed.

Lemma mext_preserves_no_embedded_ptrs: forall td eop t1 t2 gv gv',
  mext td eop t1 t2 gv = Some gv' -> no_embedded_ptrs gv'.
Proof.
  intros.
  unfold mext in H.
  remember (GV2val td gv) as R.
  destruct t1; tinv H.
    destruct t2; tinv H.
    destruct R; eauto using undef__no_embedded_ptrs.
    destruct v; eauto using undef__no_embedded_ptrs.
    destruct eop; inv H; simpl; auto.

    destruct_typ t2; tinv H.
    destruct (floating_point_order f f0); tinv H.
    destruct R; eauto using undef__no_embedded_ptrs.
    destruct v; eauto using undef__no_embedded_ptrs.
    destruct eop; tinv H; simpl; auto.
    destruct f0; inv H; unfold val2GV; simpl; auto.
Qed.

Lemma mext_preserves_no_alias: forall td eop t1 t2 gv gv' gv0,
  mext td eop t1 t2 gv = Some gv' -> no_alias gv' gv0.
Proof.
  intros.
  apply no_embedded_ptrs__no_alias.
  apply mext_preserves_no_embedded_ptrs in H; auto.
Qed.

Lemma mext_preserves_valid_ptrs: forall td eop t1 t2 gv gv' bd,
  mext td eop t1 t2 gv = Some gv' -> valid_ptrs bd gv'.
Proof.
  intros.
  apply no_embedded_ptrs__valid_ptrs.
  apply mext_preserves_no_embedded_ptrs in H; auto.
Qed.

Lemma mbitcast_inv: forall t1 t2 gv1 gv2,
  mbitcast t1 gv1 t2 = ret gv2 -> gv1 = gv2.
Proof.
  intros.
  unfold mbitcast in H.
  destruct t1; tinv H.
    destruct t2; inv H; auto.
    destruct t2; inv H; auto.
Qed.

Lemma mcast_inv: forall td cop t1 t2 gv1 gv2,
  mcast td cop t1 t2 gv1 = ret gv2 -> gv2 = gv1 \/ gundef td t2 = ret gv2.
Proof.
  intros.
  unfold mcast in H.
  destruct cop; auto;
    try
    match goal with
    | H : mbitcast _ _ _ = ret _ |- _ => apply mbitcast_inv in H; subst; auto
    end.
Qed.

Lemma mbitcast_preserves_no_alias: forall t1 t2 gv gv' gv0,
  mbitcast t1 gv t2 = Some gv' ->
  no_alias gv gv0 -> no_alias gv' gv0.
Proof.
  intros.
  apply mbitcast_inv in H. subst. auto.
Qed.

Lemma mcast_preserves_no_alias: forall td cop t1 t2 gv gv' gv0,
  mcast td cop t1 t2 gv = Some gv' ->
  no_alias gv gv0 -> no_alias gv' gv0.
Proof.
  intros.
  apply mcast_inv in H.
  destruct H as [H | H]; subst; eauto using undef_disjoint_with_ptr.
Qed.

Lemma mc2undefs_valid_ptrs: forall blk l0, valid_ptrs blk (mc2undefs l0).
Proof. induction l0; simpl; auto. Qed.

Lemma undef_valid_ptrs: forall g td t1 blk
  (Hc2g : ret g = gundef td t1), valid_ptrs blk g.
Proof.
  unfold gundef. intros.
  inv_mbind'. simpl. apply mc2undefs_valid_ptrs.
Qed.

Lemma mcast_preserves_valid_ptrs: forall td cop t1 t2 gv gv' bd,
  mcast td cop t1 t2 gv = Some gv' -> valid_ptrs bd gv -> valid_ptrs bd gv'.
Proof.
  intros.
  apply mcast_inv in H.
  destruct H as [H | H]; subst; eauto using undef_valid_ptrs.
Qed.

Lemma no_alias_prop1: forall b i1 m1 i2 m2 g,
  no_alias ((Vptr b i1, m1) :: nil) g -> no_alias ((Vptr b i2, m2) :: nil) g.
Proof.
  induction g as [|[]]; simpl; intros; auto.
    destruct v; auto.
    destruct H. simpl; auto.
Qed.

Lemma GV2ptr_inv: forall g1 td v,
  ret v = GV2ptr td (getPointerSize td) g1 ->
  exists b, exists ofs, exists m, g1 = (Vptr b ofs, m)::nil /\ v = Vptr b ofs.
Proof.
  intros.
  unfold GV2ptr in H.
  destruct g1 as [|[]]; tinv H.
  destruct v0; tinv H.
  destruct g1 as [|[]]; inv H.
  unfold ptr2GV. unfold val2GV. eauto.
Qed.

Lemma GV2ptr_preserves_no_alias: forall g1 td g2 v,
  no_alias g1 g2 ->
  ret v = GV2ptr td (getPointerSize td) g1 ->
  no_alias (ptr2GV td v) g2.
Proof.
  intros. apply GV2ptr_inv in H0. destruct H0 as [b [ofs [m [J1 J2]]]]; subst.
  unfold ptr2GV. unfold val2GV. eapply no_alias_prop1; eauto.
Qed.

Lemma GV2ptr_preserves_valid_ptrs: forall bd g1 td v,
  valid_ptrs bd g1 ->
  ret v = GV2ptr td (getPointerSize td) g1 ->
  valid_ptrs bd (ptr2GV td v).
Proof.
  intros. apply GV2ptr_inv in H0. destruct H0 as [b [ofs [m [J1 J2]]]]; subst.
  unfold ptr2GV. unfold val2GV. simpl in *. auto.
Qed.

Lemma mgep_inv: forall td v1 t1 l1 v2,
  ret v2 = mgep td t1 v1 l1 ->
  exists b, exists ofs1, exists ofs2, v1 = Vptr b ofs1 /\ v2 = Vptr b ofs2.
Proof.
  intros.
  unfold mgep in *.
  destruct v1; tinv H.
  destruct l1; tinv H.
  destruct (mgetoffset td (typ_array 0%nat t1) (z :: l1)) as [[]|]; inv H.
  eauto.
Qed.

Lemma mgep_preserves_no_alias: forall td v t1 l1 v0 gv,
  no_alias (ptr2GV td v) gv ->
  ret v0 = mgep td t1 v l1 ->
  no_alias (ptr2GV td v0) gv.
Proof.
  intros.
  apply mgep_inv in H0. destruct H0 as [b [ofs1 [ofs2 [J1 J2]]]]; subst.
  unfold ptr2GV in *. unfold val2GV in *. eapply no_alias_prop1; eauto.
Qed.

Lemma mgep_preserves_valid_ptrs: forall td v t1 l1 v0 bd,
  valid_ptrs bd (ptr2GV td v) ->
  ret v0 = mgep td t1 v l1 ->
  valid_ptrs bd (ptr2GV td v0).
Proof.
  intros.
  apply mgep_inv in H0. destruct H0 as [b [ofs1 [ofs2 [J1 J2]]]]; subst.
  simpl in *. auto.
Qed.

Lemma nonptr_no_embedded_ptrs: forall v t td,
  (forall b ofs, v <> Vptr b ofs) -> no_embedded_ptrs (val2GV td v t).
Proof.
  intros.
  destruct v; simpl; auto.
    assert (H1:=@H b i0). congruence.
Qed.

Lemma micmp_int_preserves_no_embedded_ptrs: forall td cop gv1 gv2 gv',
  micmp_int td cop gv1 gv2 = Some gv' -> no_embedded_ptrs gv'.
Proof.
  intros.
  unfold micmp_int in H.
  destruct (GV2val td gv1); eauto using undef__no_embedded_ptrs.
  destruct v; eauto using undef__no_embedded_ptrs.
  destruct (GV2val td gv2); eauto using undef__no_embedded_ptrs.
  destruct v; eauto using undef__no_embedded_ptrs.
Opaque Val.cmp Val.cmpu.
  destruct cop; inv H;
    apply nonptr_no_embedded_ptrs;
      try solve [auto | apply cmp_isnt_ptr | apply cmpu_isnt_ptr].
Transparent Val.cmp Val.cmpu.
Qed.

Lemma micmp_int_preserves_no_alias: forall td cop gv1 gv2 gv' gv0,
  micmp_int td cop gv1 gv2 = Some gv' -> no_alias gv' gv0.
Proof.
  intros.
  apply no_embedded_ptrs__no_alias.
  apply micmp_int_preserves_no_embedded_ptrs in H; auto.
Qed.

Lemma micmp_int_preserves_valid_ptrs: forall td cop gv1 gv2 bd gv',
  micmp_int td cop gv1 gv2 = Some gv' -> valid_ptrs bd gv'.
Proof.
  intros.
  apply no_embedded_ptrs__valid_ptrs.
  apply micmp_int_preserves_no_embedded_ptrs in H; auto.
Qed.

Lemma micmp_preserves_no_alias: forall td cop t1 gv1 gv2 gv' gv0,
  micmp td cop t1 gv1 gv2 = Some gv' -> no_alias gv' gv0.
Proof.
  intros.
  unfold micmp in H.
  destruct t1; tinv H; eauto using undef_disjoint_with_ptr.
    eapply micmp_int_preserves_no_alias; eauto.
Qed.

Lemma micmp_preserves_valid_ptrs: forall td cop t1 gv1 gv2 gv' bd,
  micmp td cop t1 gv1 gv2 = Some gv' -> valid_ptrs bd gv'.
Proof.
  intros.
  unfold micmp in H.
  destruct t1; tinv H; eauto using undef_valid_ptrs.
    eapply micmp_int_preserves_valid_ptrs; eauto.
Qed.

Lemma mfcmp_preserves_no_alias: forall td fop fp gv1 gv2 gv' gv0,
  mfcmp td fop fp gv1 gv2 = Some gv' -> no_alias gv' gv0.
Proof.
  intros.
  unfold mfcmp in H.
  destruct (GV2val td gv1); eauto using undef_disjoint_with_ptr.
  destruct v; eauto using undef_disjoint_with_ptr.
  destruct (GV2val td gv2); eauto using undef_disjoint_with_ptr.
  destruct v; eauto using undef_disjoint_with_ptr.
  apply no_embedded_ptrs__no_alias.
  destruct fp; tinv H;
    destruct fop; inv H; apply nonptr_no_embedded_ptrs;
      try solve [auto | apply Vfalse_isnt_ptr | apply Vtrue_isnt_ptr |
                 apply val_of_bool_isnt_ptr].
Qed.

Lemma mfcmp_preserves_valid_ptrs: forall td fop fp gv1 gv2 gv' bd,
  mfcmp td fop fp gv1 gv2 = Some gv' -> valid_ptrs bd gv'.
Proof.
  intros.
  unfold mfcmp in H.
  destruct (GV2val td gv1); eauto using undef_valid_ptrs.
  destruct v; eauto using undef_valid_ptrs.
  destruct (GV2val td gv2); eauto using undef_valid_ptrs.
  destruct v; eauto using undef_valid_ptrs.
  apply no_embedded_ptrs__valid_ptrs.
  destruct fp; tinv H;
    destruct fop; inv H; apply nonptr_no_embedded_ptrs;
      try solve [auto | apply Vfalse_isnt_ptr | apply Vtrue_isnt_ptr |
                 apply val_of_bool_isnt_ptr].
Qed.

Lemma no_alias_with_blk_split: forall g2 b g1,
  no_alias_with_blk (g1++g2) b ->
  no_alias_with_blk g1 b /\ no_alias_with_blk g2 b.
Proof.
  induction g1 as [|[]]; simpl; intros; auto.
    destruct v; auto.
    destruct H. apply IHg1 in H0. destruct H0. split; auto.
Qed.

Lemma no_alias_split: forall g2 g1 g,
  no_alias (g1++g2) g -> no_alias g1 g /\ no_alias g2 g.
Proof.
  induction g as [|[]]; simpl; intros; auto.
    destruct v; auto.

    destruct H. apply IHg in H0. destruct H0.
    apply no_alias_with_blk_split in H. destruct H.
    repeat split; auto.
Qed.

Lemma valid_ptrs_split: forall bd g2 g1,
  valid_ptrs bd (g1++g2) -> valid_ptrs bd g1 /\ valid_ptrs bd g2.
Proof.
  induction g1 as [|[]]; simpl; intros; auto.
    destruct v; auto.
    destruct H. apply IHg1 in H0. destruct H0.
    repeat split; auto.
Qed.

Lemma splitGenericValue_preserves_no_alias: forall gv g0 z0 g1 g2,
  no_alias g0 gv ->
  ret (g1, g2) = splitGenericValue g0 z0 ->
  no_alias g1 gv /\ no_alias g2 gv.
Proof.
  induction g0 as [|[]]; simpl; intros.
    destruct (zeq z0 0).
      inv H0. split; apply no_alias_nil.
      destruct (zlt z0 0); tinv H0.

    destruct (zeq z0 0).
      inv H0. split; auto using no_alias_nil.

      destruct (zlt z0 0); tinv H0.
      inv_mbind'. inv H2.
      simpl_env in H.
      apply no_alias_split in H; auto.
      destruct H.
      apply IHg0 in HeqR; auto.
      destruct HeqR. split; auto.
      simpl_env. apply no_alias_app; auto.
Qed.

Lemma splitGenericValue_preserves_valid_ptrs: forall bd g0 z0 g1 g2,
  valid_ptrs bd g0 ->
  ret (g1, g2) = splitGenericValue g0 z0 ->
  valid_ptrs bd g1 /\ valid_ptrs bd g2.
Proof.
  induction g0 as [|[]]; simpl; intros.
    destruct (zeq z0 0).
      inv H0. auto.
      destruct (zlt z0 0); tinv H0.

    destruct (zeq z0 0).
      inv H0. simpl. auto.

      destruct (zlt z0 0); tinv H0.
      inv_mbind'. inv H2.
      simpl_env in H.
      assert (valid_ptrs bd [(v,m)] /\ valid_ptrs bd g0) as J.
        simpl.
        destruct v; auto.
          destruct H; auto.
      destruct J as [J1 J2].
      apply IHg0 in HeqR; auto.
      destruct HeqR.
      split; auto.
        simpl_env.
        apply valid_ptrs_app; auto.
Qed.

Lemma extractGenericValue_preserves_no_alias: forall td gv t1 g0 g1 l0,
  no_alias g0 gv -> ret g1 = extractGenericValue td t1 g0 l0 -> no_alias g1 gv.
Proof.
  intros.
  unfold extractGenericValue in *.
  inv_mbind'.
  remember (mget td g0 z t) as R.
  destruct R; eauto using undef_disjoint_with_ptr.
  inv H1.
  unfold mget in HeqR1.
  destruct (getTypeStoreSize td t); tinv HeqR1.
  simpl in HeqR1.
  inv_mbind'. inv H2.
  eapply splitGenericValue_preserves_no_alias in HeqR2; eauto.
  destruct HeqR2.
  eapply splitGenericValue_preserves_no_alias in HeqR1; eauto.
  destruct HeqR1; auto.
  destruct_if; eauto.
Qed.

Lemma extractGenericValue_preserves_valid_ptrs: forall td g1 t1 g0 bd l0,
  valid_ptrs bd g0 -> ret g1 = extractGenericValue td t1 g0 l0 ->
  valid_ptrs bd g1.
Proof.
  intros.
  unfold extractGenericValue in *.
  inv_mbind'.
  remember (mget td g0 z t) as R.
  destruct R; eauto using undef_valid_ptrs.
  inv H1.
  unfold mget in HeqR1.
  destruct (getTypeStoreSize td t); tinv HeqR1.
  simpl in HeqR1.
  inv_mbind'. inv H2.
  eapply splitGenericValue_preserves_valid_ptrs in HeqR2; eauto.
  destruct HeqR2.
  eapply splitGenericValue_preserves_valid_ptrs in HeqR1; eauto.
  destruct HeqR1; auto.
  destruct_if; eauto.
Qed.

Lemma insertGenericValue_preserves_no_alias: forall td gv t1 t2 g0 g1 g2 l0,
  no_alias g0 gv -> no_alias g1 gv ->
  ret g2 = insertGenericValue td t1 g0 l0 t2 g1 -> no_alias g2 gv.
Proof.
  intros.
  unfold insertGenericValue in *.
  inv_mbind'.
  remember (mset td g0 z t2 g1) as R.
  destruct R; eauto using undef_disjoint_with_ptr.
  inv H2.
  unfold mset in HeqR1.
  destruct (getTypeStoreSize td t2); tinv HeqR1.
  simpl in HeqR1.
  destruct (n =n= length g1); tinv HeqR1.
  inv_mbind'. inv H3.
  eapply splitGenericValue_preserves_no_alias in HeqR2; eauto.
  destruct HeqR2.
  eapply splitGenericValue_preserves_no_alias in HeqR1; eauto.
  destruct HeqR1.
  destruct_if; eauto.
  repeat apply no_alias_app; auto.
Qed.

Lemma insertGenericValue_preserves_valid_ptrs: forall td t1 t2 g0 g1 g2 l0 bd,
  valid_ptrs bd g0 -> valid_ptrs bd g1 ->
  ret g2 = insertGenericValue td t1 g0 l0 t2 g1 -> valid_ptrs bd g2.
Proof.
  intros.
  unfold insertGenericValue in *.
  inv_mbind'.
  remember (mset td g0 z t2 g1) as R.
  destruct R; eauto using undef_valid_ptrs.
  inv H2.
  unfold mset in HeqR1.
  destruct (getTypeStoreSize td t2); tinv HeqR1.
  simpl in HeqR1.
  destruct (n =n= length g1); tinv HeqR1.
  inv_mbind'. inv H3.
  eapply splitGenericValue_preserves_valid_ptrs in HeqR2; eauto.
  destruct HeqR2.
  eapply splitGenericValue_preserves_valid_ptrs in HeqR1; eauto.
  destruct HeqR1.
  destruct_if; eauto.
  repeat apply valid_ptrs_app; auto.
Qed.

Lemma mbop_preserves_no_embedded_ptrs: forall td bop0 sz0 gv1 gv2 gv3,
  mbop td bop0 sz0 gv1 gv2 = Some gv3 -> no_embedded_ptrs gv3.
Proof.
  intros.
  unfold mbop in H.
  destruct (GV2val td gv1); eauto using undef__no_embedded_ptrs.
  destruct v; eauto using undef__no_embedded_ptrs.
  destruct (GV2val td gv2); eauto using undef__no_embedded_ptrs.
  destruct v; eauto using undef__no_embedded_ptrs.
  destruct (eq_nat_dec (wz + 1) (Size.to_nat sz0));
    eauto using undef__no_embedded_ptrs.
  destruct bop0; inv H;
    apply nonptr_no_embedded_ptrs;
      try solve [apply add_isnt_ptr | apply sub_isnt_ptr | apply mul_isnt_ptr |
                 apply divu_isnt_ptr | apply divs_isnt_ptr | apply modu_isnt_ptr |
                 apply mods_isnt_ptr | apply shl_isnt_ptr | apply shrx_isnt_ptr |
                 apply shr_isnt_ptr | apply and_isnt_ptr | apply or_isnt_ptr |
                 apply xor_isnt_ptr].
Qed.

Lemma mbop_preserves_no_alias: forall td bop0 sz0 gv1 gv2 gv3 gv,
  mbop td bop0 sz0 gv1 gv2 = Some gv3 ->
  no_alias gv3 gv.
Proof.
  intros.
  apply no_embedded_ptrs__no_alias.
  apply mbop_preserves_no_embedded_ptrs in H; auto.
Qed.

Lemma mbop_preserves_valid_ptrs: forall td bop0 sz0 gv1 gv2 gv3 bd,
  mbop td bop0 sz0 gv1 gv2 = Some gv3 ->
  valid_ptrs bd gv3.
Proof.
  intros.
  apply no_embedded_ptrs__valid_ptrs.
  apply mbop_preserves_no_embedded_ptrs in H; auto.
Qed.

Lemma mfbop_preserves_no_embedded_ptrs: forall td fbop0 fp0 gv1 gv2 gv3,
  mfbop td fbop0 fp0 gv1 gv2 = Some gv3 -> no_embedded_ptrs gv3.
Proof.
  intros.
  unfold mfbop in H.
  destruct (GV2val td gv1); eauto using undef__no_embedded_ptrs.
  destruct v; eauto using undef__no_embedded_ptrs.
  destruct (GV2val td gv2); eauto using undef__no_embedded_ptrs.
  destruct v; eauto using undef__no_embedded_ptrs.
  destruct fp0; tinv H; destruct fbop0; inv H; simpl; auto.
Qed.

Lemma mfbop_preserves_no_alias: forall td fbop0 fp0 gv1 gv2 gv3 gv0,
  mfbop td fbop0 fp0 gv1 gv2 = Some gv3 -> no_alias gv3 gv0.
Proof.
  intros.
  apply no_embedded_ptrs__no_alias.
  apply mfbop_preserves_no_embedded_ptrs in H; auto.
Qed.

Lemma mfbop_preserves_valid_ptrs: forall td fbop0 fp0 gv1 gv2 gv3 bd,
  mfbop td fbop0 fp0 gv1 gv2 = Some gv3 -> valid_ptrs bd gv3.
Proof.
  intros.
  apply no_embedded_ptrs__valid_ptrs.
  apply mfbop_preserves_no_embedded_ptrs in H; auto.
Qed.

Lemma undef_valid_ptrs__disjoint_with_ptr: forall g td t1 blk g'
  (Hc2g : ret g = gundef td t1), no_alias g g' /\ valid_ptrs blk g.
Proof.
  intros.
  split.
    eapply undef_disjoint_with_ptr; eauto.
    eapply undef_valid_ptrs; eauto.
Qed.

Lemma wf_als_split: forall maxb M als als',
  wf_als maxb M (als++als') -> wf_als maxb M als /\ wf_als maxb M als'.
Proof.
  intros.
  destruct H as [J1 J2].
  apply NoDup_split in J1.
  destruct J1 as [J11 J12].
  split.
    split; auto.
      intros. apply J2. apply in_or_app; auto.
    split; auto.
      intros. apply J2. apply in_or_app; auto.
Qed.

Lemma free_preserves_mload_aux_inv: forall blk lo hi b Mem Mem'
  (Hfree:Mem.free Mem blk lo hi = ret Mem') mc ofs gvsa,
  mload_aux Mem' mc b ofs = ret gvsa ->
  mload_aux Mem mc b ofs = ret gvsa.
Proof.
  induction mc; simpl; intros; auto.
    inv_mbind'. symmetry in HeqR0.
    apply IHmc in HeqR0.
    rewrite HeqR0.
    erewrite <- Mem.load_free; eauto.
      rewrite <- HeqR. auto.
      eapply Mem.load_free'; eauto.
Qed.

Lemma free_preserves_mload_inv: forall TD Mem' gptr ty al gvsa Mem mptr0
  (H1 : mload TD Mem' gptr ty al = ret gvsa)
  (H2 : free TD Mem mptr0 = ret Mem'),
  mload TD Mem gptr ty al = ret gvsa.
Proof.
  intros.
  apply mload_inv in H1.
  destruct H1 as [b [ofs [m [mc [J1 [J2 J3]]]]]]; subst.
  unfold mload. simpl. rewrite J2.
  apply free_inv in H2.
  destruct H2 as [blk' [ofs' [hi [lo [J4 [J5 [J6 J7]]]]]]].
  eapply free_preserves_mload_aux_inv; eauto.
Qed.

Lemma nextblock_free: forall TD M gv M',
  free TD M gv = ret M' -> Mem.nextblock M = Mem.nextblock M'.
Proof.
  intros.
  apply free_inv in H.
  destruct H as [blk' [ofs' [hi [lo [J4 [J5 [J6 J7]]]]]]].
  apply Mem.nextblock_free in J7. auto.
Qed.

Lemma free_preserves_wf_lc: forall TD Mem' Mem mptr0
  (H2 : free TD Mem mptr0 = ret Mem') lc
  (Hwf: wf_lc Mem lc),
  wf_lc Mem' lc.
Proof.
  unfold wf_lc.
  intros.
  apply Hwf in H.
  apply free_inv in H2.
  destruct H2 as [blk' [ofs' [hi [lo [J4 [J5 [J6 J7]]]]]]].
  erewrite Mem.nextblock_free; eauto.
Qed.

Lemma free_preserves_mload_aux: forall Mem blk lo hi Mem' b
  (Hfree: Mem.free Mem blk lo hi = ret Mem') (Hneq: blk <> b) mc ofs gv,
  mload_aux Mem mc b ofs = ret gv ->
  mload_aux Mem' mc b ofs = ret gv.
Proof.
  induction mc; simpl; intros; auto.
    inv_mbind'. symmetry in HeqR0.
    apply IHmc in HeqR0.
    rewrite HeqR0.
    erewrite Mem.load_free; eauto.
      rewrite <- HeqR. auto.
Qed.

Lemma free_preserves_mload: forall TD Mem Mem' t al gv gptr gvsa
  (H0 : no_alias gptr gvsa)
  (H1 : free TD Mem gptr = ret Mem')
  (H2 : mload TD Mem gvsa t al = ret gv),
  mload TD Mem' gvsa t al = ret gv.
Proof.
  intros.
  apply free_inv in H1.
  destruct H1 as [blk [ofs [hi [lo [J4 [J5 [J6 J7]]]]]]].
  apply mload_inv in H2.
  destruct H2 as [b [ofs' [m [mc [J1 [J2 J3]]]]]]; subst.
  unfold mload. simpl. rewrite J2.
  symmetry in J4.
  apply GV2ptr_inv in J4.
  destruct J4 as [b1 [ofs1 [m1 [J8 J9]]]]; subst.
  inv J9.
  simpl in H0. destruct H0. destruct H. clear H1 H0.
  eapply free_preserves_mload_aux in J3; eauto.
Qed.

Lemma free_preserves_wf_Mem : forall maxb TD M M' mptr0
  (Hfree: free TD M mptr0 = ret M')
  (Hwf: wf_Mem maxb TD M),
  wf_Mem maxb TD M'.
Proof.
  intros. destruct Hwf as [J1 J2].
  unfold wf_Mem.
  erewrite <- nextblock_free; eauto.
  split; auto.
    intros.
    eapply free_preserves_mload_inv in H; eauto.
Qed.

Lemma free_preserves_wf_als : forall maxb TD M M' mptr0 als
  (Hfree: free TD M mptr0 = ret M')
  (Hwf: wf_als maxb M als),
  wf_als maxb M' als.
Proof.
  intros. destruct Hwf as [J1 J2].
  split; auto.
    intros.
    apply J2 in H.
    erewrite <- nextblock_free; eauto.
Qed.

Lemma free_allocas_preserves_mload_inv: forall TD gptr ty al gvsa als Mem' Mem
  (H1 : mload TD Mem' gptr ty al = ret gvsa)
  (H2 : free_allocas TD Mem als = ret Mem'),
  mload TD Mem gptr ty al = ret gvsa.
Proof.
  induction als; simpl; intros.
    inv H2. auto.

    inv_mbind'.
    eapply free_preserves_mload_inv with (Mem':=m); eauto.
Qed.

Lemma nextblock_free_allocas: forall TD als M M',
  free_allocas TD M als = ret M' -> Mem.nextblock M = Mem.nextblock M'.
Proof.
  induction als; simpl; intros.
    inv H. auto.

    inv_mbind'. symmetry in HeqR.
    apply nextblock_free in HeqR; auto.
    rewrite HeqR. auto.
Qed.

Lemma free_allocas_preserves_wf_lc: forall td lc als Mem Mem',
  free_allocas td Mem als = ret Mem' -> wf_lc Mem lc -> wf_lc Mem' lc.
Proof.
  induction als; simpl; intros.
    inv H. auto.

    inv_mbind'. symmetry in HeqR.
    eapply free_preserves_wf_lc in HeqR; eauto.
Qed.

Lemma updateAddAL__wf_lc: forall gv3 Mem0 lc id0
  (Hwfgv: valid_ptrs (Mem.nextblock Mem0) gv3) (Hwflc: wf_lc Mem0 lc),
  wf_lc Mem0 (updateAddAL (GVsT DGVs) lc id0 gv3).
Proof.
  intros. unfold wf_lc in *. intros.
  destruct (id_dec id0 id1); subst.
    rewrite lookupAL_updateAddAL_eq in H. inv H. eauto.

    rewrite <- lookupAL_updateAddAL_neq in H; auto.
    eapply Hwflc; eauto.
Qed.

Lemma valid_ptrs__trans: forall bound1 bound2 gv,
  valid_ptrs bound1 gv -> bound1 <= bound2 -> valid_ptrs bound2 gv.
Proof.
  induction gv as [|[]]; simpl; intros; auto.
    destruct v; auto.
      destruct H. split; auto. omega.
Qed.

Lemma free_allocas_preserves_wf_Mem: forall maxb td als Mem Mem',
  wf_Mem maxb td Mem -> free_allocas td Mem als = ret Mem' ->
  wf_Mem maxb td Mem'.
Proof.
  induction als; simpl; intros.
    inv H0. auto.

    inv_mbind'.
    symmetry in HeqR.
    eapply free_preserves_wf_Mem in HeqR; eauto.
Qed.

Lemma free_allocas_preserves_wf_als : forall maxb TD als als0 M M'
  (Hfree: free_allocas TD M als0 = ret M')
  (Hwf: wf_als maxb M als),
  wf_als maxb M' als.
Proof.
  induction als0; simpl; intros.
    inv Hfree. auto.

    inv_mbind'.
    symmetry in HeqR.
    eapply free_preserves_wf_als in HeqR; eauto.
Qed.

Lemma BOP_preserves_no_alias: forall TD lc gl bop0 sz0 v1 v2 gvs3 gvsa,
  BOP TD lc gl bop0 sz0 v1 v2 = ret gvs3 ->
  no_alias gvs3 gvsa.
Proof.
  intros.
  unfold BOP in H.
  inv_mbind'. eapply mbop_preserves_no_alias in H0; eauto.
Qed.

Lemma BOP_preserves_no_embedded_ptrs: forall TD lc gl bop0 sz0 v1 v2 gvs3,
  BOP TD lc gl bop0 sz0 v1 v2 = ret gvs3 -> no_embedded_ptrs gvs3.
Proof.
  intros.
  unfold BOP in H.
  inv_mbind'. eapply mbop_preserves_no_embedded_ptrs in H0; eauto.
Qed.

Lemma FBOP_preserves_no_alias: forall TD lc gl fbop0 fp v1 v2 gvs3 gvsa,
  FBOP TD lc gl fbop0 fp v1 v2 = ret gvs3 ->
  no_alias gvs3 gvsa.
Proof.
  intros.
  unfold FBOP in H.
  inv_mbind'. eapply mfbop_preserves_no_alias in H0; eauto.
Qed.

Lemma FBOP_preserves_no_embedded_ptrs: forall TD lc gl fbop0 fp v1 v2 gvs3,
  FBOP TD lc gl fbop0 fp v1 v2 = ret gvs3 -> no_embedded_ptrs gvs3.
Proof.
  intros.
  unfold FBOP in H.
  inv_mbind'. eapply mfbop_preserves_no_embedded_ptrs in H0; eauto.
Qed.

Lemma undef__valid_lift_ptrs: forall g td t1 blk
  (Hc2g : ret g = gundef td t1), valid_ptrs blk ($ g # t1 $).
Proof.
  unfold gundef. intros.
  inv_mbind'.
Local Transparent gv2gvs.
  unfold gv2gvs. simpl. unfold MDGVs.gv2gvs. apply mc2undefs_valid_ptrs.
Opaque gv2gvs.
Qed.

Fixpoint mld_st_mld_rel (gvs1 gvs1':GenericValue) v2 b1 b2 ofs1 ofs2 m2 M 
  :=
match gvs1, gvs1' with
| nil, nil => True
| (v1, m1)::gvs2, (v1', m1')::gvs2' =>
    m1 = m1' /\ Mem.ld_st_ld_rel v1 v1' v2 b1 b2 ofs1 ofs2 m1 m2 M /\
    mld_st_mld_rel gvs2 gvs2' v2 b1 b2 (ofs1+size_chunk m1) ofs2 m2 M
| _, _ => False
end.

Lemma store_preserves_mload_aux_inv': forall b1 b2 v2 m2 Mem' Mem ofs2 
  (Hst: Mem.store m2 Mem b2 ofs2 v2 = ret Mem') mc ofs1 gvs0,
  mload_aux Mem' mc b1 ofs1 = ret gvs0 ->
  exists gvs2 : GenericValue,
     mload_aux Mem mc b1 ofs1 = ret gvs2 /\
     mld_st_mld_rel gvs0 gvs2 v2 b1 b2 ofs1 ofs2 m2 Mem.
Proof.
  induction mc; simpl; intros.
    inv H. 
    exists nil. 
    split; simpl; auto.

    inv_mbind'. symmetry in HeqR0.
    apply IHmc in HeqR0.
    destruct HeqR0 as [gvs2 [J1 J2]].
    rewrite J1.
    eapply Mem.store_preserves_load_inv_aux' in Hst; eauto.
    destruct Hst as [v1' [J3 J4]].
    rewrite J3.
    exists ((v1',a)::gvs2).
    split; simpl; auto.
Qed.

Fixpoint mld_mst_mld_rel (gvs1 gvs1':GenericValue) gvs2 b1 b2 ofs1 ofs2 M 
  :=
match gvs2 with
| nil => True
| (v2, m2)::gvs2' =>
    mld_st_mld_rel gvs1 gvs1' v2 b1 b2 ofs1 ofs2 m2 M /\
    mld_mst_mld_rel gvs1 gvs1' gvs2' b1 b2 ofs1 (ofs2+size_chunk m2) M
end.

(*
Lemma mstore_aux_preserves_mload_aux_inv': forall mc b1 ofs1 b2 gvs1 gvs0 Mem' Mem ofs2,
  mload_aux Mem' mc b1 ofs1 = ret gvs0 ->
  mstore_aux Mem gvs1 b2 ofs2 = ret Mem' ->
  exists gvs2 : GenericValue,
     mload_aux Mem mc b1 ofs1 = ret gvs2 /\
     mld_mst_mld_rel gvs0 gvs2 gvs1 b1 b2 ofs1 ofs2 Mem.
Proof.
  induction gvs1 as [|[]]; simpl; intros.
    inv H0. exists gvs0. split; auto.
  
    inv_mbind'.
    eapply IHgvs1 in H2; eauto.
    destruct H2 as [gvs2 [J1 J2]].
    symmetry in HeqR.
    eapply store_preserves_mload_aux_inv' in HeqR; eauto.
    destruct HeqR as [gvs3 [J3 J4]].
    exists gvs3.
    split; auto.
    split.

    intros.
    apply J2 in H0.
    destruct H0 as [H0 | H0]; subst; 
      try solve [right; intros; subst; right; eauto].
    apply J4 in H0. 
    destruct H0 as [H0 | H0]; subst; auto.
      right. intros. apply H0 in H1. destruct H1; subst; auto.
Qed.
*)

Lemma store_preserves_mload_aux_inv: forall b1 b2 v2 m2 Mem' Mem ofs2
  (Hst: Mem.store m2 Mem b2 ofs2 v2 = ret Mem') mc ofs1 gvs0,
  mload_aux Mem' mc b1 ofs1 = ret gvs0 ->
  exists gvs2 : GenericValue,
     mload_aux Mem mc b1 ofs1 = ret gvs2 /\
     (forall v m,
      In (v, m) gvs0 -> In (v, m) gvs2 \/
      (forall b0 ofs0, v = Vptr b0 ofs0 -> v = v2 /\ m = m2)).
Proof.
  induction mc; simpl; intros.
    inv H.
    exists nil.
    split; auto.
      intros. inv H.

    inv_mbind'. symmetry in HeqR0.
    apply IHmc in HeqR0.
    destruct HeqR0 as [gvs2 [J1 J2]].
    rewrite J1.
    eapply Mem.store_preserves_load_inv in Hst; eauto.
    destruct Hst as [v1' [J3 J4]].
    rewrite J3.
    exists ((v1',a)::gvs2).
    split; auto.
      intros. simpl.
      simpl in H. destruct H as [H | H]; subst.
        inv H.
        destruct J4 as [J4 | J4]; subst; auto.

        apply J2 in H.
        destruct H as [H | H]; auto.
Qed.

Lemma mstore_aux_preserves_mload_aux_inv: forall mc b1 ofs1 gvs0 b2 gvs1 Mem' Mem ofs2,
  mload_aux Mem' mc b1 ofs1 = ret gvs0 ->
  mstore_aux Mem gvs1 b2 ofs2 = ret Mem' ->
  exists gvs2 : GenericValue,
     mload_aux Mem mc b1 ofs1 = ret gvs2 /\
     (forall v m,
      In (v, m) gvs0 -> In (v, m) gvs2 \/
      (forall b0 ofs0, v = Vptr b0 ofs0 -> In (v, m) gvs1)).
Proof.
  induction gvs1 as [|[]]; simpl; intros.
    inv H0. exists gvs0. split; auto.

    inv_mbind'.
    apply IHgvs1 in H2; auto.
    destruct H2 as [gvs2 [J1 J2]].
    symmetry in HeqR.
    eapply store_preserves_mload_aux_inv in HeqR; eauto.
    destruct HeqR as [gvs3 [J3 J4]].
    exists gvs3.
    split; auto.
    intros.
    apply J2 in H0.
    destruct H0 as [H0 | H0]; subst;
      try solve [right; intros; subst; right; eauto].
    apply J4 in H0.
    destruct H0 as [H0 | H0]; subst; auto.
      right. intros. apply H0 in H1. destruct H1; subst; auto.
Qed.

Ltac destruct_ldst :=
match goal with
| H1 : mload _ _ _ _ _ = ret _,
  H2 : mstore _ _ _ _ _ _ = ret _ |- _ =>
  apply store_inv in H2;
  destruct H2 as [b [ofs [J5 J4]]];
  apply mload_inv in H1;
  destruct H1 as [b1 [ofs1 [m1 [mc [J1 [J2 J3]]]]]]; subst;
  unfold mload; simpl; rewrite J2;
  symmetry in J5; apply GV2ptr_inv in J5;
  destruct J5 as [b2 [ofs2 [m2 [J6 J7]]]]; subst; inv J7
end.

Lemma mstore_preserves_mload_inv: forall TD Mem' gptr ty al gvs0 Mem gvs1 t
  mp2 (H1 : mload TD Mem' gptr ty al = ret gvs0) align
  (H2 : mstore TD Mem mp2 t gvs1 align = Some Mem'),
  exists gvs2, mload TD Mem gptr ty al = ret gvs2 /\
     (forall v m,
      In (v, m) gvs0 -> In (v, m) gvs2 \/
      (forall b0 ofs0, v = Vptr b0 ofs0 -> In (v, m) gvs1)).
Proof.
  intros. destruct_ldst.
  eapply mstore_aux_preserves_mload_aux_inv; eauto.
Qed.

Lemma store_preserves_mload: forall b1 b2 v2 m2 Mem' Mem ofs2
  (Hneq: b1 <> b2) (Hst: Mem.store m2 Mem b2 ofs2 v2 = ret Mem') mc ofs1 gvs0,
  mload_aux Mem mc b1 ofs1 = ret gvs0 ->
  mload_aux Mem' mc b1 ofs1 = ret gvs0.
Proof.
  induction mc; simpl; intros; auto.
    inv_mbind'. symmetry in HeqR0.
    apply IHmc in HeqR0.
    rewrite HeqR0.
    erewrite Mem.load_store_other; eauto.
    rewrite <- HeqR. auto.
Qed.

Lemma mstore_aux_preserves_mload_aux: forall mc b1 ofs1 gvs0 b2
  (Hneq: b1 <> b2) gvs1 Mem' Mem ofs2,
  mload_aux Mem mc b1 ofs1 = ret gvs0 ->
  mstore_aux Mem gvs1 b2 ofs2 = ret Mem' ->
  mload_aux Mem' mc b1 ofs1 = ret gvs0.
Proof.
  induction gvs1 as [|[]]; simpl; intros.
    inv H0. auto.

    inv_mbind'.
    apply IHgvs1 in H2; auto.
    eapply store_preserves_mload; eauto.
Qed.

Lemma mstore_preserves_mload: forall TD Mem' gptr ty al gvs0 Mem gv1 t
  mp2 (H1 : mload TD Mem gptr ty al = ret gvs0) align
  (H2 : mstore TD Mem mp2 t gv1 align = Some Mem')
  (Hna: no_alias mp2 gptr),
  mload TD Mem' gptr ty al = ret gvs0.
Proof.
  intros. destruct_ldst.
  simpl in Hna. destruct Hna as [[Hna _] _ ].
  eapply mstore_aux_preserves_mload_aux; eauto.
Qed.

Lemma store_preserves_mload': forall b1 b2 v2 m2 Mem' Mem ofs2
  (Hst: Mem.store m2 Mem b2 ofs2 v2 = ret Mem') mc ofs1 gvs0,
  mload_aux Mem mc b1 ofs1 = ret gvs0 ->
  exists gvs1, mload_aux Mem' mc b1 ofs1 = ret gvs1.
Proof.
  induction mc; simpl; intros.
    inv H. eauto.

    inv_mbind'. symmetry in HeqR0.
    apply IHmc in HeqR0.
    destruct HeqR0 as [gvs1 HeqR0].
    rewrite HeqR0.
    assert (exists v1', Mem.load a Mem' b1 ofs1 = Some v1') as J.
      symmetry in HeqR.
      apply Mem.load_valid_access in HeqR.
      apply Mem.valid_access_load.
      eapply Mem.store_valid_access_1 in Hst; eauto.
    destruct J as [v1' J].
    rewrite J.
    exists ((v1',a)::gvs1). auto.
Qed.

Lemma mstore_aux_preserves_mload_aux': forall mc b1 ofs1 b2
  gvs1 gvs0 Mem' Mem ofs2,
  mload_aux Mem mc b1 ofs1 = ret gvs0 ->
  mstore_aux Mem gvs1 b2 ofs2 = ret Mem' ->
  exists gvs1, mload_aux Mem' mc b1 ofs1 = ret gvs1.
Proof.
  induction gvs1 as [|[]]; simpl; intros.
    inv H0. eauto.

    inv_mbind'.
    symmetry in HeqR.
    eapply store_preserves_mload' in HeqR; eauto.
    destruct HeqR as [gvs2 HeqR].
    eapply IHgvs1 in H2; eauto.
Qed.

Lemma mstore_preserves_mload': forall TD Mem' gptr ty al gvs0 Mem gv1 t
  mp2 (H1 : mload TD Mem gptr ty al = ret gvs0) align
  (H2 : mstore TD Mem mp2 t gv1 align = Some Mem'),
  exists gvs1, mload TD Mem' gptr ty al = ret gvs1.
Proof.
  intros. destruct_ldst.
  eapply mstore_aux_preserves_mload_aux'; eauto.
Qed.

Lemma no_alias_with_blk__neq_blk: forall b1 b2 ofs2 m2 gvs,
  no_alias_with_blk gvs b1 -> In (Vptr b2 ofs2, m2) gvs -> b2 <> b1.
Proof.
  induction gvs as [|[]]; simpl; intros; auto.
    destruct H0 as [H0 | H0].
      inv H0.
      destruct H; auto.

      destruct v; eauto.
Qed.

Lemma no_alias_with_blk_overlap: forall gvs1 gvs2 b gvs0,
  no_alias_with_blk gvs1 b ->
  no_alias_with_blk gvs2 b ->
  (forall (v : val) (m : AST.memory_chunk),
       In (v, m) gvs0 ->
       In (v, m) gvs2 \/
       (forall (b0 : Values.block) (ofs0 : int32),
        v = Vptr b0 ofs0 -> In (v, m) gvs1)) ->
  no_alias_with_blk gvs0 b.
Proof.
  induction gvs0 as [|[]]; simpl; intros; auto.
    destruct v; eauto.
    split; eauto.
    edestruct H1 as [J | J]; eauto.
      eapply no_alias_with_blk__neq_blk in J; eauto.
      eapply no_alias_with_blk__neq_blk in H; eauto.
Qed.

Lemma no_alias_overlap: forall gvs1 gvs2 gvs0 gvsa,
  no_alias gvs1 gvsa ->
  no_alias gvs2 gvsa ->
  (forall (v : val) (m : AST.memory_chunk),
       In (v, m) gvs0 ->
       In (v, m) gvs2 \/
       (forall (b0 : Values.block) (ofs0 : int32),
        v = Vptr b0 ofs0 -> In (v, m) gvs1)) ->
  no_alias gvs0 gvsa.
Proof.
  induction gvsa as [|[]]; simpl; intros; auto.
    destruct v; eauto.
    destruct H as [J1 J2].
    destruct H0 as [J3 J4].
    split; eauto.
      eapply no_alias_with_blk_overlap in H1; eauto.
Qed.

Lemma nextblock_mstore_aux: forall b gvs M ofs M',
  mstore_aux M gvs b ofs = ret M' ->
  Mem.nextblock M = Mem.nextblock M'.
Proof.
  induction gvs as [|[]]; simpl; intros.
    inv H. auto.

    inv_mbind'.
    apply IHgvs in H1.
    symmetry in HeqR.
    apply Mem.nextblock_store in HeqR.
    rewrite <- HeqR. auto.
Qed.

Lemma nextblock_mstore: forall TD M gv1 M' mp2 t align0,
  mstore TD M mp2 t gv1 align0 = ret M' ->
  Mem.nextblock M = Mem.nextblock M'.
Proof.
  intros.
  apply store_inv in H.
  destruct H as [blk' [ofs' [J1 J2]]].
  apply nextblock_mstore_aux in J2; auto.
Qed.

Lemma mstore_preserves_wf_lc: forall TD M' M mp2 t gv1 align
  (Hst: mstore TD M mp2 t gv1 align = Some M') lc
  (Hwf: wf_lc M lc),
  wf_lc M' lc.
Proof.
  unfold wf_lc.
  intros.
  apply Hwf in H.
  erewrite <- nextblock_mstore; eauto.
Qed.

Lemma in_valid_ptrs: forall bd m b ofs gvs,
  valid_ptrs bd gvs -> In (Vptr b ofs, m) gvs -> b < bd.
Proof.
  induction gvs as [|[]]; simpl; intros.
    inv H0.

    destruct H0 as [H0 | H0].
      inv H0.
      destruct H; auto.

      destruct v; eauto.
      destruct H; eauto.
Qed.

Lemma valid_ptrs_overlap: forall gvs1 gvs2 bd gvs0,
  valid_ptrs bd gvs1 ->
  valid_ptrs bd gvs2 ->
  (forall (v : val) (m : AST.memory_chunk),
       In (v, m) gvs0 ->
       In (v, m) gvs2 \/
       (forall (b0 : Values.block) (ofs0 : int32),
        v = Vptr b0 ofs0 -> In (v, m) gvs1)) ->
  valid_ptrs bd gvs0.
Proof.
  induction gvs0 as [|[]]; simpl; intros; auto.
    destruct v; eauto.
    edestruct H1 as [J1 | J1]; eauto.
      split; eauto.
      eapply in_valid_ptrs in J1; eauto.

      split; eauto.
      eapply in_valid_ptrs in H; eauto.
Qed.

Lemma mstore_preserves_wf_als : forall TD M mp2 t gv1 align M' maxb als
  (Hst: mstore TD M mp2 t gv1 align = Some M')
  (Hwf: wf_als maxb M als),
  wf_als maxb M' als.
Proof.
  intros. destruct Hwf as [J1 J2].
  split; auto.
    intros.
    apply J2 in H; auto.
    erewrite <- nextblock_mstore; eauto.
Qed.

Fixpoint mcs2uninits (mc:list AST.memory_chunk) : GenericValue :=
match mc with
| nil => nil
| c::mc => (Vundef, c)::mcs2uninits mc
end.

Lemma alloc_preserves_mload_aux_inv': forall M M' mb lo hi b
  (Hal : Mem.alloc M lo hi = (M', mb)) mc ofs gvs1
  (H : mload_aux M' mc b ofs = ret gvs1),
  mload_aux M mc b ofs = ret gvs1 /\ b <> mb \/
  gvs1 = mcs2uninits mc /\ b = mb.
Proof.
  induction mc; simpl; intros.
    inv H.
    destruct (zeq b mb); subst; auto.

    inv_mbind'.
    symmetry in HeqR.
    assert (J:=HeqR).
    apply Mem.load_valid_access in J.
    eapply Mem.valid_access_alloc_inv in J; eauto.
    symmetry in HeqR0. apply IHmc in HeqR0.
    destruct (eq_block b mb); subst.
      destruct J as [J1 [J2 J3]].
      erewrite Mem.load_alloc_same' in HeqR; eauto.
      inv HeqR.
      destruct HeqR0 as [[J4 J5] | [J4 J5]]; subst;
        try solve [congruence | tauto].

      destruct HeqR0 as [[J4 J5] | [J4 J5]]; subst; try solve [congruence].
      left.
      rewrite J4.
      split; auto.
        apply Mem.valid_access_implies with (p2:=Nonempty) in J; try constructor.
        apply Mem.valid_access_valid_block in J.
        erewrite Mem.load_alloc_unchanged in HeqR; eauto.
        rewrite HeqR. auto.
Qed.

Lemma mcs2uninits_spec: forall v m mc, In (v, m) (mcs2uninits mc) -> v = Vundef.
Proof.
  induction mc; simpl; intros.
    inv H.

    destruct H as [H | H]; auto.
      inv H; auto.
Qed.

Lemma alloc_preserves_mload_aux_inv: forall M M' mb lo hi b
  (Hal : Mem.alloc M lo hi = (M', mb)) mc ofs gvs1
  (H : mload_aux M' mc b ofs = ret gvs1),
  mload_aux M mc b ofs = ret gvs1 /\ b <> mb \/
  (forall v m, In (v, m) gvs1 -> v = Vundef) /\ b = mb.
Proof.
  intros.
  eapply alloc_preserves_mload_aux_inv' in H; eauto.
  destruct H as [H | H]; auto.
  right.
  destruct H; subst.
  split; auto.
    intros.
    eapply mcs2uninits_spec; eauto.
Qed.

Ltac destruct_allocld :=
match goal with
| Hal : malloc _ _ _ _ _ = ret _,
  H : mload _ _ _ _ _ = ret _ |- _ =>
  apply mload_inv in H;
  destruct H as [b [ofs [m [mc [J1 [J2 J3]]]]]]; subst;
  apply malloc_inv in Hal;
  destruct Hal as [n [J4 [J5 J6]]];
  unfold mload; simpl; rewrite J2
end.

Lemma malloc_preserves_mload_inv': forall TD M M' mb align0 gn tsz
  (Hal : malloc TD M tsz gn align0 = ret (M', mb))
  gptr gvs1 ty al
  (H : mload TD M' gptr ty al = ret gvs1),
  mload TD M gptr ty al = ret gvs1 /\ no_alias_with_blk gptr mb \/
  (forall mc, flatten_typ TD ty = ret mc ->
    gvs1 = mcs2uninits mc) /\ ~ no_alias_with_blk gptr mb.
Proof.
  intros. destruct_allocld.
  eapply alloc_preserves_mload_aux_inv' in J3; eauto.
  destruct J3 as [[J3 J7]|[J3 J7]]; subst; auto.
    right. split; try tauto. intros. inv H. auto.
Qed.

Lemma malloc_preserves_mload_inv: forall TD M M' mb align0 gn tsz
  (Hal : malloc TD M tsz gn align0 = ret (M', mb))
  gptr gvs1 ty al
  (H : mload TD M' gptr ty al = ret gvs1),
  mload TD M gptr ty al = ret gvs1 /\ no_alias_with_blk gptr mb \/
  (forall v m, In (v, m) gvs1 -> v = Vundef) /\ ~ no_alias_with_blk gptr mb.
Proof.
  intros.
  destruct_allocld.
  eapply alloc_preserves_mload_aux_inv in J3; eauto.
  destruct J3 as [[J3 J7]|[J3 J7]]; subst; auto.
    right. split; auto. intros [J7 J8]; auto.
Qed.

Lemma mload__flatten_typ: forall TD M gptr ty al gvs,
  mload TD M gptr ty al = ret gvs -> exists mc, flatten_typ TD ty = ret mc.
Proof.
  intros.
  apply mload_inv in H.
  destruct H as [b [ofs [m [mc [J1 [J2 J3]]]]]]; subst; eauto.
Qed.

Lemma no_alias_undef: forall m g, no_alias [(Vundef, m)] g.
Proof.
  induction g as [|[]]; simpl; intros; auto.
    destruct v; auto.
Qed.

Lemma undefs_disjoint_with_ptr: forall gvs2 gvs1
  (Hc2g : forall v m, In (v, m) gvs1 -> v = Vundef),
  no_alias gvs1 gvs2.
Proof.
  induction gvs1; simpl; intros.
    apply no_alias_nil.

    simpl_env.
    apply no_alias_app; eauto.
    destruct a.
    assert ((v, m) = (v, m) \/ In (v, m) gvs1) as J. auto.
    apply Hc2g in J. subst.
    apply no_alias_undef.
Qed.

Lemma nextblock_malloc: forall TD M tsz gn M' align0 mb,
  malloc TD M tsz gn align0 = ret (M', mb) ->
  Mem.nextblock M + 1 = Mem.nextblock M'.
Proof.
  intros.
  apply malloc_inv in H.
  destruct H as [n [J1 [J2 J3]]].
  apply Mem.nextblock_alloc in J3.
  rewrite J3. omega.
Qed.

Lemma malloc_result: forall TD M tsz gn M' align0 mb,
  malloc TD M tsz gn align0 = ret (M', mb) ->
  mb = Mem.nextblock M.
Proof.
  intros.
  apply malloc_inv in H.
  destruct H as [n [J1 [J2 J3]]].
  apply Mem.alloc_result in J3; auto.
Qed.

Lemma alloc_preserves_mload_aux: forall M M' mb lo hi b
  (Hal : Mem.alloc M lo hi = (M', mb)) mc ofs gvs1
  (H : mload_aux M mc b ofs = ret gvs1),
  mload_aux M' mc b ofs = ret gvs1.
Proof.
  induction mc; simpl; intros; auto.
    inv_mbind'.
    symmetry in HeqR, HeqR0.
    eapply Mem.load_alloc_other in HeqR; eauto.
    rewrite HeqR.
    apply IHmc in HeqR0.
    rewrite HeqR0. auto.
Qed.

Lemma malloc_preserves_mload: forall TD M M' mb align0 gn tsz
  (Hal : malloc TD M tsz gn align0 = ret (M', mb))
  gptr gvs1 ty al
  (H : mload TD M gptr ty al = ret gvs1),
  mload TD M' gptr ty al = ret gvs1.
Proof.
  intros. destruct_allocld.
  eapply alloc_preserves_mload_aux in J3; eauto.
Qed.

Lemma undefs_valid_ptrs: forall bd gvs1
  (Hc2g : forall v m, In (v, m) gvs1 -> v = Vundef),
  valid_ptrs bd gvs1.
Proof.
  induction gvs1 as [|[]]; simpl; intros; auto.
    destruct v; eauto.
    assert ((Vptr b i0, m) = (Vptr b i0, m) \/ In (Vptr b i0, m) gvs1) as J.
      auto.
    apply Hc2g in J. congruence.
Qed.

Lemma malloc_preserves_wf_Mem : forall maxb TD M tsz gn align0 M' mb
  (Hmlc: malloc TD M tsz gn align0 = ret (M', mb))
  (Hwf: wf_Mem maxb TD M),
  wf_Mem maxb TD M'.
Proof.
  intros. destruct Hwf as [J1 J2].
  assert (Mem.nextblock M + 1 = Mem.nextblock M') as EQ.
    eapply nextblock_malloc; eauto.
  split.
    rewrite <- EQ.
    intros.
    eapply malloc_preserves_mload_inv in H; eauto.
    destruct H as [[G _]| [G _]]; subst; eauto.
      apply J1 in G. eapply valid_ptrs__trans; eauto. omega.
      eapply undefs_valid_ptrs; eauto.

    omega.
Qed.

Lemma malloc_preserves_wf_als : forall maxb TD M M' tsz gn align0 mb als
  (Hmalloc: malloc TD M tsz gn align0 = ret (M', mb))
  (Hbd: maxb < Mem.nextblock M) (Hwf: wf_als maxb M als),
  wf_als maxb M' (mb::als).
Proof.
  intros. destruct Hwf as [J1 J2].
  split.
    constructor; auto.
      intro J. apply J2 in J.
      apply malloc_result in Hmalloc. subst. omega.

    intros.
    simpl in H.
    erewrite <- nextblock_malloc; eauto.
    apply malloc_result in Hmalloc. subst.
    destruct H as [H | H]; subst.
      omega.
      apply J2 in H. omega.
Qed.

Lemma ptr_no_alias__no_alias_with_blk : forall b i0 m gvs2,
  no_alias [(Vptr b i0, m)] gvs2 -> no_alias_with_blk gvs2 b.
Proof.
  induction gvs2 as [|[]]; simpl; intros; auto.
    destruct v; auto.
    destruct H. destruct H.
    split; auto.
Qed.

Lemma no_alias_sym: forall gvs2 gvs1, no_alias gvs1 gvs2 -> no_alias gvs2 gvs1.
Proof.
  induction gvs1 as [|[]]; simpl; intros; auto.
    simpl_env in H.
    apply no_alias_split in H.
    destruct H as [H1 H2].
    destruct v; auto.
    split; auto.
      apply ptr_no_alias__no_alias_with_blk in H1; auto.
Qed.

Lemma null_disjoint_with_ptr: forall mb ofs m,
  mb > 0 -> no_alias null [(Vptr mb ofs, m)].
Proof.
  intros. simpl. unfold Mem.nullptr.
  repeat split; auto. intro. subst. omega.
Qed.

Lemma uninits_disjoint_with_ptr: forall n mb ofs m,
  no_alias (uninits n) [(Vptr mb ofs, m)].
Proof.
  intros.
  induction n; simpl; auto.
Qed.

Lemma uninits_valid_ptrs__disjoint_with_ptr: forall n mb ofs m bd,
  no_alias (uninits n) [(Vptr mb ofs, m)] /\
  valid_ptrs bd (uninits n).
Proof.
  intros.
  split. apply uninits_disjoint_with_ptr.
         apply uninits_valid_ptrs.
Qed.

Definition zeroconst2GV_aux_disjoint_with_runtime_ptr_prop S td (t:typ) 
  (H:wf_styp S td t) :=
  forall los nts acc (Heq: td = (los, nts)) nts' 
  (Hsub:exists nts0, nts'=nts0++nts) (Huniq: uniq nts')
  maxb gl g mb ofs m
  (Hwfg: wf_globals maxb gl)
  (Hc2g : zeroconst2GV_aux (los,nts') acc t = ret g)
  (Hle: maxb < mb)
  (Hnc: forall id5 gv5, 
          lookupAL _ nts id5 <> None ->
          lookupAL _ acc id5 = Some (Some gv5) ->
          no_alias gv5 [(Vptr mb ofs, m)] /\ valid_ptrs (maxb + 1) gv5),
  no_alias g [(Vptr mb ofs, m)] /\ valid_ptrs (maxb + 1) g.

Definition zeroconsts2GV_aux_disjoint_with_runtime_ptr_prop sdt 
  (H:wf_styp_list sdt) :=
  let 'lsdt := unmake_list_system_targetdata_typ sdt in
  let '(lsd, lt) := split lsdt in
  forall S td los nts acc (Heq: td = (los, nts)) nts' 
  (Hsub:exists nts0, nts'=nts0++nts) (Huniq: uniq nts') maxb gl g mb ofs m
  (Hnc: forall id5 gv5, 
          lookupAL _ nts id5 <> None ->
          lookupAL _ acc id5 = Some (Some gv5) ->
          no_alias gv5 [(Vptr mb ofs, m)] /\ valid_ptrs (maxb + 1) gv5)
  (Heq': eq_system_targetdata S td lsd)
  (Hwfg: wf_globals maxb gl)
  (Hc2g : zeroconsts2GV_aux (los,nts') acc (make_list_typ lt) = ret g)
  (Hle: maxb < mb),
  no_alias g [(Vptr mb ofs, m)] /\ valid_ptrs (maxb + 1) g.

Lemma zeroconst2GV_aux_disjoint_with_runtime_ptr_mutrec :
  (forall S TD t H, zeroconst2GV_aux_disjoint_with_runtime_ptr_prop S TD t H) /\
  (forall sdt H, zeroconsts2GV_aux_disjoint_with_runtime_ptr_prop sdt H).
Proof.
  (wfstyp_cases (apply wf_styp_mutind; 
    unfold zeroconst2GV_aux_disjoint_with_runtime_ptr_prop, 
           zeroconsts2GV_aux_disjoint_with_runtime_ptr_prop) Case);
    intros; subst; try (simpl in Hc2g; uniq_result); try solve [simpl; auto].

Case "wf_styp_function".
  split.
    apply null_disjoint_with_ptr. destruct Hwfg. omega.
    apply null_valid_ptrs. destruct Hwfg. omega.

Case "wf_styp_structure".
  remember (split
              (unmake_list_system_targetdata_typ
                (make_list_system_targetdata_typ
                   (map_list_typ
                      (fun typ_ : typ => (system5, (los, nts):targetdata, typ_))
                      typ_list)))) as R.
  destruct R as [lsd lt].
  assert (make_list_typ lt = typ_list) as EQ1. 
    eapply make_list_typ_spec2; eauto.
  subst.
  assert (eq_system_targetdata system5 (los, nts) lsd) as EQ2.
    eapply wf_styp__feasible_typ_aux_mutrec_struct; eauto.
  subst. 
  inv_mbind. symmetry_ctx.
  eapply H in HeqR0; eauto 2.
  destruct g0; inv H1; auto.

Case "wf_styp_array".
  destruct sz5 as [|s]; 
    try solve [inv Hc2g; auto using uninits_valid_ptrs__disjoint_with_ptr].
    inv_mbind'. symmetry_ctx.
    eapply H with (ofs:=ofs)(m:=m) in HeqR; eauto.
    assert (no_alias
      (g0 ++ uninits (Size.to_nat s0 - sizeGenericValue g0))
      [(Vptr mb ofs, m)] /\
      valid_ptrs (maxb + 1)
        (g0 ++ uninits (Size.to_nat s0 - sizeGenericValue g0))) as J.
      destruct HeqR.
      split.
        apply no_alias_app; auto.
          apply uninits_disjoint_with_ptr.
        apply valid_ptrs_app; auto.
          apply uninits_valid_ptrs.
    destruct J as [J1 J2].
    split.
      apply no_alias_app; auto.
      apply no_alias_repeatGV; auto.

      apply valid_ptrs_app; auto.
      apply valid_ptrs_repeatGV; auto.

Case "wf_styp_pointer".
  split.
    apply null_disjoint_with_ptr. destruct Hwfg. omega.
    apply null_valid_ptrs. destruct Hwfg. omega.

Case "wf_styp_namedt".
  inv_mbind. eauto.

Case "wf_styp_nil".
  simpl. intros. uniq_result.
  split; simpl; auto.

Case "wf_styp_cons".
Local Opaque no_alias valid_ptrs.
  destruct targetdata5 as [los nts]. simpl.
  remember (split (unmake_list_system_targetdata_typ l')) as R.
  destruct R as [lsd lt]. simpl.
  intros. subst. 
  apply eq_system_targetdata_cons_inv in Heq'. 
  destruct Heq' as [H2 [EQ1 EQ2]]; subst. uniq_result.
  inv_mbind. symmetry_ctx.
  eapply H in HeqR1; eauto 1. clear H.
  eapply H0 in HeqR0; eauto 1. clear H0.
  destruct HeqR1. destruct HeqR0.
  split.
    apply no_alias_app; auto.
    apply no_alias_app; auto.
    apply uninits_disjoint_with_ptr.

    apply valid_ptrs_app; auto.
    apply valid_ptrs_app; auto.
    apply uninits_valid_ptrs.
Transparent no_alias valid_ptrs.
Qed.

Lemma noncycled__disjoint_with_runtime_ptr: forall S los nts maxb gl ofs mb m
  (Hwfg: wf_globals maxb gl) (H: noncycled S los nts) (Huniq: uniq nts)
  id5 lt nts2 nts1 (EQ: nts = nts1 ++ (id5,lt) :: nts2) nts' (Huniq': uniq nts') 
  (Hsub: exists nts0, nts'=nts0++nts) gv
  (Hz: zeroconst2GV_aux (los, nts')
         (zeroconst2GV_for_namedts (los, nts') los nts2) (typ_struct lt) = 
           Some gv)
  (Hle: maxb < mb),
  no_alias gv [(Vptr mb ofs, m)] /\ valid_ptrs (maxb + 1) gv.
Proof.
Local Opaque no_alias valid_ptrs.
  induction 2; simpl; intros; subst.
    symmetry in EQ.    
    apply app_eq_nil in EQ.
    destruct EQ as [_ EQ].
    congruence.

    inv Huniq.
    destruct nts1 as [|[]]; inv EQ.
      destruct zeroconst2GV_aux_disjoint_with_runtime_ptr_mutrec as [J _].
      eapply J in H0; eauto.
      assert (exists nts0 : list namedt, nts' = nts0 ++ nts2) as G.
        destruct Hsub as [nts0 Hsub]; subst. 
        exists (nts0 ++ [(id0, lt)]). simpl_env. auto.
      eapply H0 in G; simpl; eauto 1.  
      intros id5 gv5 H1 H2.
      apply lookupAL_middle_inv' in H1.
      destruct H1 as [l0 [l1 [l2 HeqR]]].
      assert (J':=HeqR). subst.
      eapply IHnoncycled with (nts':=nts') in J'; eauto.
        eapply zeroconst2GV_for_namedts_spec1 in H2; eauto.
            
      assert (nts1 ++ (id0, lt) :: nts2 = nts1 ++ (id0, lt) :: nts2) as EQ. auto.
      eapply IHnoncycled with (nts':=nts') in EQ; eauto.
        destruct Hsub as [nts0 Hsub]; subst. 
        exists (nts0 ++ [(i0, l0)]). simpl_env. auto.
Transparent no_alias valid_ptrs.
Qed.

Lemma zeroconst2GV_disjoint_with_runtime_ptr: forall S t maxb gl g td mb ofs m
  (Hwft: wf_typ S td t) (Hwfg: wf_globals maxb gl)
  (Hc2g : ret g = zeroconst2GV td t)
  (Hle: maxb < mb),
  no_alias g [(Vptr mb ofs, m)] /\ valid_ptrs (maxb + 1) g.
Proof. 
  intros. destruct td as [los nts].
  unfold zeroconst2GV in *. inv Hwft.
  destruct zeroconst2GV_aux_disjoint_with_runtime_ptr_mutrec as [J' _].
  assert (exists nts0 : list namedt, nts = nts0 ++ nts) as G'.
    exists nil. auto.
  eapply J'; eauto.
  intros id5 gv5 J5 J6.
  apply lookupAL_middle_inv' in J5.
  destruct J5 as [lt5 [l1 [l2 HeqR]]]. subst.
  eapply noncycled__disjoint_with_runtime_ptr
    with (nts':=l1 ++ (id5, lt5) :: l2) in H1; eauto.
    eapply zeroconst2GV_for_namedts_spec1 in J6; eauto.
Qed.

Lemma wf_global_disjoint_with_runtime_ptr: forall maxb ofs m
  mb (Hle : maxb < mb) g0 (Hwfg : wf_global maxb g0),
  no_alias g0 [(Vptr mb ofs, m)] /\ valid_ptrs (maxb + 1) g0.
Proof.
  induction g0 as [|[]]; simpl; intros.
    split; auto using no_alias_nil.

    destruct v; auto.
      destruct Hwfg as [J1 J2].
      apply_clear IHg0 in J2.
      simpl in *. destruct J2. destruct H.
      split.
        split; auto.
        split; auto.
          intro. subst. contradict J1. omega.

        split; auto. omega.
Qed.

Lemma wf_globals_disjoint_with_runtime_ptr: forall maxb ofs m
  (g0 : GenericValue) i0  mb (Hle : maxb < mb) gl (Hwfg : wf_globals maxb gl)
  (HeqR : ret g0 = lookupAL GenericValue gl i0),
  no_alias g0 [(Vptr mb ofs, m)] /\ valid_ptrs (maxb + 1) g0.
Proof.
  induction gl as [|[]]; intros.
    inv HeqR.

    destruct Hwfg. simpl in H0.
    destruct H0 as [J1 J2].
    simpl in HeqR.
    destruct (i0 == i1); subst.
      inv HeqR. eapply wf_global_disjoint_with_runtime_ptr; eauto.
      apply IHgl; auto. split; auto.
Qed.

Lemma nonptr_no_alias: forall v t td mb ofs0 m0,
  (forall b ofs, v <> Vptr b ofs) ->
  no_alias (val2GV td v t) [(Vptr mb ofs0, m0)].
Proof.
  intros.
  destruct v; simpl; auto.
    assert (H1:=@H b i0). congruence.
Qed.

Definition const2GV_disjoint_with_runtime_ptr_prop S td c t 
  (H:wf_const S td c t) :=
  forall maxb gl g mb t0 ofs m
  (Hwfg: wf_globals maxb gl)
  (Hc2g : _const2GV td gl c = ret (g, t0))
  (Hle: maxb < mb),
  t = t0 /\ no_alias g [(Vptr mb ofs, m)] /\ valid_ptrs (maxb+1) g.

Definition list_const2GV_disjoint_with_runtime_ptr_prop sdct 
  (H:wf_const_list sdct) :=
  let 'lsdct := unmake_list_system_targetdata_const_typ sdct in
  let '(lsdc, lt) := split lsdct in
  let '(lsd, lc) := split lsdc in
  let '(ls, ld) := split lsd in
  forall S td maxb gl mb ofs m 
  (Hwfls: wf_list_targetdata_typ' S td lsd)
  (Hwfg: wf_globals maxb gl)
  (Hle: maxb < mb),
  (forall gv t,
    (forall t0, In t0 lt -> t0 = t) ->
    _list_const_arr2GV td gl t (make_list_const lc) = Some gv ->
    no_alias gv [(Vptr mb ofs, m)] /\ valid_ptrs (maxb+1) gv
  ) /\
  (forall gv lt',
    _list_const_struct2GV td gl (make_list_const lc) = Some (gv,lt') ->
    lt' = make_list_typ lt /\ 
    no_alias gv [(Vptr mb ofs, m)] /\ valid_ptrs (maxb+1) gv
  ).

Lemma const2GV_disjoint_with_runtime_ptr_mutrec :
  (forall S td c t H, const2GV_disjoint_with_runtime_ptr_prop S td c t H) /\
  (forall sdct H, list_const2GV_disjoint_with_runtime_ptr_prop sdct H).
Proof.
  (wfconst_cases (apply wf_const_mutind; 
                  unfold const2GV_disjoint_with_runtime_ptr_prop, 
                         list_const2GV_disjoint_with_runtime_ptr_prop) Case);
    intros; try simpl in Hc2g; uniq_result; inv_mbind'.
Case "wfconst_zero".
  eauto using zeroconst2GV_disjoint_with_runtime_ptr.
Case "wfconst_int".
  simpl. auto.
Case "wfconst_floatingpoint".
  destruct floating_point5; inv Hc2g; simpl; auto.
Case "wfconst_undef".
  eauto using undef_valid_ptrs__disjoint_with_ptr.
Case "wfconst_null".
  split; auto.
  inv Hwfg.
  split.
    apply null_disjoint_with_ptr. omega.
    apply null_valid_ptrs. omega.
Case "wfconst_array". Focus.
  inv_mbind.
  remember (split
             (unmake_list_system_targetdata_const_typ
                (make_list_system_targetdata_const_typ
                   (map_list_const
                      (fun const_ : const =>
                       (system5, targetdata5:targetdata, const_, typ5)) 
                      const_list)))) as R.
  destruct R as [lsdc lt]. 
  remember (split lsdc) as R'.
  destruct R' as [lsd lc].
  remember (split lsd) as R''.
  destruct R'' as [ls ld].
  match goal with
  | H3: match _ with
        | 0%nat => _
        | S _ => _ 
        end = _ |- _ => 
  rewrite e in H3; unfold Size.to_nat in *;
  destruct sz5; inv H3; split; auto
  end.
    simpl. auto.

    destruct (@H system5 targetdata5 maxb gl mb ofs m) as [J1 J2]; 
      try solve 
      [destruct targetdata5; eauto using const2GV_typsize_mutind_array'].
    symmetry_ctx.
    assert (make_list_const lc = const_list) as EQ.
      eapply make_list_const_spec2; eauto.
    rewrite <- EQ in HeqR. subst.
    rewrite length_unmake_make_list_const in e. 
    apply J1 in HeqR; eauto using make_list_const_spec4.
Unfocus.

Case "wfconst_struct". Focus.
  remember (split 
              (unmake_list_system_targetdata_const_typ
                 (make_list_system_targetdata_const_typ
                    (map_list_const_typ
                      (fun (const_ : const) (typ_ : typ) =>
                       (system5, (layouts5, namedts5):targetdata, const_, typ_))
                      const_typ_list)))) as R.
  destruct R as [lsdc lt]. 
  remember (split lsdc) as R'.
  destruct R' as [lsd lc].
  remember (split lsd) as R''.
  destruct R'' as [ls ld].
  destruct (@H system5 (layouts5, namedts5) maxb gl mb ofs m) as [J1 J2];
    eauto using const2GV_typsize_mutind_struct'.
  destruct_if.
  destruct g0; inv H2.
    split; simpl; auto.
    split; auto.
      symmetry in HeqR.
      erewrite <- map_list_const_typ_spec2 in HeqR; eauto.
      erewrite <- map_list_const_typ_spec1 in e; eauto.
      apply J2 in HeqR.
      destruct HeqR as [J5 [J6 J7]]; subst.
      split; eauto using uninits_valid_ptrs__disjoint_with_ptr.
Unfocus.

Case "wfconst_gid".
  split; auto.
    eapply wf_globals_disjoint_with_runtime_ptr; eauto.
Case "wfconst_trunc_int".
  split; auto.
  split.
    eapply mtrunc_preserves_no_alias; eauto.
    eapply mtrunc_preserves_valid_ptrs; eauto.
Case "wfconst_trunc_fp".
  split; auto.
  split.
    eapply mtrunc_preserves_no_alias; eauto.
    eapply mtrunc_preserves_valid_ptrs; eauto.
Case "wfconst_zext".
  split; auto.
  split.
    eapply mext_preserves_no_alias; eauto.
    eapply mext_preserves_valid_ptrs; eauto.
Case "wfconst_sext".
  split; auto.
  split.
    eapply mext_preserves_no_alias; eauto.
    eapply mext_preserves_valid_ptrs; eauto.
Case "wfconst_fpext".
  split; auto.
  split.
    eapply mext_preserves_no_alias; eauto.
    eapply mext_preserves_valid_ptrs; eauto.
Case "wfconst_ptrtoint".
  split; auto.
  split.
    eauto using undef_disjoint_with_ptr.
    eauto using undef_valid_ptrs.
Case "wfconst_inttoptr".
  split; auto.
  split.
    eauto using undef_disjoint_with_ptr.
    eauto using undef_valid_ptrs.
Case "wfconst_bitcast".
  symmetry_ctx.
  eapply H in HeqR; eauto. destruct HeqR as [J1 [J2 J3]].
  assert (mcast targetdata5 castop_bitcast t (typ_pointer typ2) g0 = ret g) 
    as J.
    simpl. auto.
  split; auto.
  split.
    eapply mcast_preserves_no_alias; eauto.
    eapply mcast_preserves_valid_ptrs; eauto.
Case "wfconst_gep". Focus.
  symmetry in HeqR.
  eapply H with (ofs:=ofs)(m:=m) in HeqR; eauto.
  destruct HeqR as [J1 [J2 J3]]; subst.
  remember (getConstGEPTyp const_list (typ_pointer typ5)) as R2.
  destruct R2; tinv H2. uniq_result.
  remember (GV2ptr targetdata5 (getPointerSize targetdata5) g0) as R3.
  destruct R3; tinv H2.
    remember (intConsts2Nats targetdata5 const_list) as R4.
    destruct R4; tinv H2.
      remember (mgep targetdata5 typ5 v l0) as R5.
      destruct R5; inv H2.
        symmetry_ctx. uniq_result. 
        split; auto.
        split.
          eapply mgep_preserves_no_alias; eauto using GV2ptr_preserves_no_alias.
          eapply mgep_preserves_valid_ptrs; 
            eauto using GV2ptr_preserves_valid_ptrs.

        inv_mbind. symmetry_ctx. uniq_result. 
        split; eauto using undef_valid_ptrs__disjoint_with_ptr.
      inv_mbind. symmetry_ctx. uniq_result. 
      split; eauto using undef_valid_ptrs__disjoint_with_ptr.
    inv_mbind. symmetry_ctx. uniq_result. 
    split; eauto using undef_valid_ptrs__disjoint_with_ptr.
Unfocus.

Case "wfconst_select". 
  destruct_if; eauto.
Case "wfconst_icmp".
  split; auto.
  split.
    eapply micmp_preserves_no_alias; eauto.
    eapply micmp_preserves_valid_ptrs; eauto.
Case "wfconst_fcmp".
  destruct t; tinv H2. inv_mbind'.
  split; auto.
  split.
    eapply mfcmp_preserves_no_alias; eauto.
    eapply mfcmp_preserves_valid_ptrs; eauto.
Case "wfconst_extractvalue".
  symmetry_ctx.
  eapply H in HeqR; eauto.
  destruct HeqR as [J1 [J2 J3]]; subst.
  destruct e0 as [idxs [o [J5 J4]]].
  eapply getSubTypFromConstIdxs__mgetoffset in HeqR0; eauto.
  subst.
  split; auto.
  split.
    eapply extractGenericValue_preserves_no_alias; eauto.
    eapply extractGenericValue_preserves_valid_ptrs; eauto.
Case "wfconst_insertvalue".
  symmetry_ctx.
  eapply H in HeqR; eauto. clear H.
  eapply H0 in HeqR0; eauto. clear H0 H1.
  destruct HeqR as [J1 [J2 J3]]; subst.
  destruct HeqR0 as [J4 [J5 J6]]; subst.
  split; auto.
  symmetry in HeqR1.
  split.
    eapply insertGenericValue_preserves_no_alias in HeqR1; eauto.
    eapply insertGenericValue_preserves_valid_ptrs in HeqR1; eauto.
Case "wfconst_bop".
  destruct t; tinv H2. inv_mbind'.
  symmetry_ctx. 
  eapply H with (ofs:=ofs)(m:=m) in HeqR; eauto.
  destruct HeqR as [J1 [J2 J3]]; subst.
  eapply H0 with (ofs:=ofs)(m:=m) in HeqR0; eauto.
  destruct HeqR0 as [J4 [J5 J6]]; subst.
  uniq_result.
  split; auto.
  split.
    eapply mbop_preserves_no_alias; eauto.
    eapply mbop_preserves_valid_ptrs; eauto.
Case "wfconst_fbop".
  destruct t; tinv H2. inv_mbind'.
  symmetry_ctx. 
  eapply H with (ofs:=ofs)(m:=m) in HeqR; eauto.
  destruct HeqR as [J1 [J2 J3]]; subst.
  eapply H0 with (ofs:=ofs)(m:=m) in HeqR0; eauto.
  destruct HeqR0 as [J4 [J5 J6]]; subst.
  uniq_result.
  split; auto.
  split.
    eapply mfbop_preserves_no_alias; eauto.
    eapply mfbop_preserves_valid_ptrs; eauto.
Case "wfconst_nil".
Local Opaque no_alias.
  simpl. intros.
  split.
    intros. uniq_result. simpl. split; auto using no_alias_nil.
    intros. uniq_result. simpl. split; auto using no_alias_nil.

Case "wfconst_cons".
Local Opaque no_alias.
  simpl.
  remember (split (unmake_list_system_targetdata_const_typ l')) as R1.
  destruct R1 as [lsdc lt].
  simpl.  
  remember (split lsdc) as R2.
  destruct R2 as [lsd lc].
  simpl.  
  remember (split lsd) as R3.
  destruct R3 as [ls ld].
  split; intros; simpl in *; inv_mbind'.
    destruct (typ_dec t t0); tinv H3.
    inv_mbind'. symmetry_ctx.
    apply wf_list_targetdata_typ_cons_inv' in Hwfls.
    destruct Hwfls as [J1 [J2 J3]]; subst.
    eapply H with (ofs:=ofs)(m:=m) in HeqR0; eauto.
    destruct HeqR0 as [J5 [J6 J7]]; subst.
    eapply H0 with (ofs:=ofs)(m:=m) in HeqR; eauto. 
    destruct HeqR as [J8 J9]. clear H H0.
    split.
      apply no_alias_app; auto.
        apply no_alias_app; auto.
        apply uninits_disjoint_with_ptr.
      apply valid_ptrs_app; auto.
        apply valid_ptrs_app; auto.
        apply uninits_valid_ptrs.

    apply wf_list_targetdata_typ_cons_inv' in Hwfls.
    destruct Hwfls as [J1' [J2' J3]]; subst.
    symmetry_ctx.
    eapply H with (ofs:=ofs)(m:=m) in HeqR0; eauto.
    destruct HeqR0 as [J5 [J6 J7]]; subst.
    eapply H0 with (ofs:=ofs)(m:=m) in HeqR; eauto. 
    destruct HeqR as [J8 [J9 J10]]; subst. clear H H0.
    split; auto.
    split.
      apply no_alias_app; auto.
      apply no_alias_app; auto.
      apply uninits_disjoint_with_ptr.

      apply valid_ptrs_app; auto.
      apply valid_ptrs_app; auto.
      apply uninits_valid_ptrs.
Global Transparent no_alias.
Qed.

Lemma cgv2gvs_preserves_no_alias: forall g0 mb ofs m t0 maxb,
  no_alias g0 [(Vptr mb ofs, m)] ->
  0 <= maxb < mb ->
  no_alias (cgv2gvs DGVs g0 t0) [(Vptr mb ofs, m)].
Proof.
  intros.
Local Transparent cgv2gvs.
  unfold cgv2gvs. simpl. unfold MDGVs.cgv2gvs. unfold cgv2gv.
  destruct g0 as [|[]]; auto.
  destruct v; auto.
  destruct g0 as [|]; auto.

  unfold cundef_gv.
  destruct_typ t0; auto.
    destruct f; auto.

    simpl. split; auto. split; auto. unfold Mem.nullptr. intro J. subst. omega.
Global Opaque cgv2gvs.
Qed.

Lemma cgv2gvs_preserves_valid_ptrs: forall g0 t0 bd,
  bd > 0 -> valid_ptrs bd g0 -> valid_ptrs bd (cgv2gvs DGVs g0 t0).
Proof.
  intros.
Local Transparent cgv2gvs.
  unfold cgv2gvs. simpl. unfold MDGVs.cgv2gvs. unfold cgv2gv.
  destruct g0 as [|[]]; auto.
  destruct v; auto.
  destruct g0 as [|]; auto.
  unfold cundef_gv.
  destruct_typ t0; auto.
    destruct f; auto.

    apply null_valid_ptrs; auto.
Global Opaque cgv2gvs.
Qed.

Lemma malloc_preserves_wf_lc_in_tail: forall TD M M' tsz gn align0 mb lc
  (Hmalloc: malloc TD M tsz gn align0 = ret (M', mb))
  (Hwf: wf_lc M lc), wf_lc M' lc.
Proof.
  unfold wf_lc.
  intros. apply Hwf in H.
  eapply valid_ptrs__trans; eauto.
  erewrite <- nextblock_malloc with (M':=M'); eauto.
  omega.
Qed.

Lemma store_preserves_mload_inv': forall b1 b2 v2 m2 Mem' Mem ofs2
  (Hneq: b1 <> b2) (Hst: Mem.store m2 Mem b2 ofs2 v2 = ret Mem') mc ofs1 gvs0,
  mload_aux Mem' mc b1 ofs1 = ret gvs0 ->
  mload_aux Mem mc b1 ofs1 = ret gvs0.
Proof.
  induction mc; simpl; intros; auto.
    inv_mbind'. symmetry in HeqR0.
    apply IHmc in HeqR0.
    rewrite HeqR0.
    erewrite <- Mem.load_store_other; eauto.
    rewrite <- HeqR. auto.
Qed.

Lemma mstore_aux_preserves_mload_inv_aux': forall mc b1 ofs1 gvs0 b2
  (Hneq: b1 <> b2) gvs1 Mem' Mem ofs2,
  mload_aux Mem' mc b1 ofs1 = ret gvs0 ->
  mstore_aux Mem gvs1 b2 ofs2 = ret Mem' ->
  mload_aux Mem mc b1 ofs1 = ret gvs0.
Proof.
  induction gvs1 as [|[]]; simpl; intros.
    inv H0. auto.

    inv_mbind'.
    apply IHgvs1 in H2; auto.
    eapply store_preserves_mload_inv'; eauto.
Qed.

Lemma mstore_preserves_mload_inv': forall TD Mem' gptr ty al gvs0 Mem gv1 t
  mp2 (H1 : mload TD Mem' gptr ty al = ret gvs0) align
  (H2 : mstore TD Mem mp2 t gv1 align = Some Mem')
  (Hna: no_alias mp2 gptr),
  mload TD Mem gptr ty al = ret gvs0.
Proof.
  intros. destruct_ldst.
  simpl in Hna. destruct Hna as [[Hna _] _ ].
  eapply mstore_aux_preserves_mload_inv_aux'; eauto.
Qed.

Axiom callExternalOrIntrinsics_preserves_mload: forall Mem fid gvsa gvs gvsv
  Mem' TD oresult ty al dck gl tret targs tr,
  callExternalOrIntrinsics TD gl Mem fid tret targs dck gvs 
    = ret (oresult, tr, Mem') ->
  mload TD Mem gvsa ty al = ret gvsv ->
  mload TD Mem' gvsa ty al = ret gvsv.

Lemma mstore_aux_mem_contents_outside: 
  forall mb ofs2 gv1 ofs1 M M' (Hst: mstore_aux M gv1 mb ofs1 = ret M')
  (Hlt: ofs1 >= ofs2),
  forall i0 : Z, i0 < ofs2 ->
    Mem.mem_contents M mb i0 = Mem.mem_contents M' mb i0.
Proof.
  induction gv1 as [|[]]; simpl; intros.
    uniq_result. auto.

    inv_mbind. 
    erewrite <- IHgv1 with (M:=m0)(ofs1:=ofs1 + size_chunk m)(M':=M'); eauto.
      symmetry in HeqR.
      apply Mem.store_mem_contents in HeqR.
      rewrite HeqR.
      rewrite update_s.
      rewrite Mem.setN_outside; auto.
        omega.

        assert (J:=@size_chunk_pos m). omega.
Qed.

Definition encode_decode_ident_prop
  (M:mem) (b:Values.block) (ofs:Z) (chunk:AST.memory_chunk) : Prop :=
forall bs, 
  bs = Mem.getN (size_chunk_nat chunk) ofs (Mem.mem_contents M b) ->
  bs = encode_val chunk (decode_val chunk bs).

Fixpoint encode_decode_ident_aux (M:mem) (mc:list AST.memory_chunk) b ofs 
  : Prop :=
match mc with
| nil => True
| c::mc' => encode_decode_ident_prop M b ofs c /\
            encode_decode_ident_aux M mc' b (ofs+size_chunk c)%Z
end.

Definition encode_decode_ident 
  (TD:TargetData) (M:mem) (ptr:mptr) (t:typ) (a:align) : Prop :=
match GV2ptr TD (getPointerSize TD) ptr with
| Some (Vptr b ofs) =>
  match flatten_typ TD t with
  | Some mc => encode_decode_ident_aux M mc b (Int.signed 31 ofs)
  | _ => False
  end
| _ => False
end.

Lemma store_preserves_encode_decode_ident_prop: forall M blk ofs v M' b chunk 
  ofs1 chunk1 (Hst: Mem.store chunk1 M blk ofs1 v = Some M') (Hneq: blk <> b)
  (Hid: encode_decode_ident_prop M b ofs chunk),
  encode_decode_ident_prop M' b ofs chunk.
Proof.
  unfold encode_decode_ident_prop in *.
  intros.
  apply Hid; auto.
  erewrite Mem.store_getN_out; eauto.
Qed.

Lemma store_preserves_encode_decode_ident_aux: forall M blk ofs' M' b chunk v
  (Hneq: blk <> b) (Hst: Mem.store chunk M blk ofs' v = Some M') mc ofs
  (Hid: encode_decode_ident_aux M mc b ofs),
  encode_decode_ident_aux M' mc b ofs.
Proof.
  induction mc; simpl; intros; auto.
    destruct Hid; split; auto.
      eapply store_preserves_encode_decode_ident_prop; eauto.
Qed.

Lemma mstore_aux_preserves_encode_decode_ident_aux: forall blk b 
  (Hneq: blk <> b) mc ofs gv ofs' M M'
  (Hst: mstore_aux M gv blk ofs' = Some M') 
  (Hid: encode_decode_ident_aux M mc b ofs),
  encode_decode_ident_aux M' mc b ofs.
Proof.
  induction gv as [|[]]; simpl; intros.
    uniq_result. auto.

    inv_mbind.
    eapply IHgv; eauto.
      eapply store_preserves_encode_decode_ident_aux; eauto.
Qed.

Lemma no_alias_GV2ptr__neq_blk: forall TD sz0 ptr1 ptr2 b1 i1 b2 i2
  (H1: GV2ptr TD sz0 ptr1 = ret Vptr b1 i1)
  (H2: GV2ptr TD sz0 ptr2 = ret Vptr b2 i2)
  (Hnoalias: no_alias ptr1 ptr2),
  b1 <> b2.
Proof.
  intros.
  destruct ptr1 as [|[[]][]]; inv H1.
  destruct ptr2 as [|[[]][]]; inv H2.
  simpl in Hnoalias. tauto.
Qed.

Lemma mstore_preserves_encode_decode_ident: forall TD M ptr1 ty al M' ptr2
  (Hnoalias: no_alias ptr2 ptr1) ty2 gv2 al2
  (Hid: encode_decode_ident TD M ptr1 ty al) 
  (Hst: mstore TD M ptr2 ty2 gv2 al2= Some M'),
  encode_decode_ident TD M' ptr1 ty al.
Proof.
  unfold encode_decode_ident. intros.
  match goal with
  | Hid: context [GV2ptr ?td ?sz ?ptr] |- _ =>
      remember (GV2ptr td sz ptr) as R;
      destruct R as [[]|]; tinv Hid
  end.
  match goal with
  | Hid: context [flatten_typ ?td ?ty] |- _ =>
      remember (flatten_typ td ty) as R;
      destruct R as [|]; tinv Hid
  end.
  apply store_inv in Hst.
  destruct Hst as [blk' [ofs' [J4 J5]]].
  eapply mstore_aux_preserves_encode_decode_ident_aux; 
    eauto using no_alias_GV2ptr__neq_blk.
Qed.

Lemma mstore_preserves_load: forall b1 b2 ofs1 m gv M1 M2 ofs2
  (Hneq: b1 <> b2 \/ ofs1 + size_chunk m <= ofs2)
  (Hst: mstore_aux M1 gv b2 ofs2 = ret M2),
  Mem.load m M1 b1 ofs1 = Mem.load m M2 b1 ofs1.
Proof.
  induction gv as [|[]]; simpl; intros; auto.
    uniq_result. auto.

    inv_mbind'. symmetry_ctx.
    transitivity (Mem.load m m1 b1 ofs1).
      eapply Mem.load_store_other in HeqR; eauto.
      destruct Hneq; auto.

      apply IHgv in H0; auto.
      destruct Hneq; auto.
      right.
      assert (J:=size_chunk_pos m0). omega.
Qed.

End MemProps.


