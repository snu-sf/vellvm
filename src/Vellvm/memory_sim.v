Require Import Memory.
Require Import Values.
Require Import Coqlib.
Require Import Integers.
Require Import AST.
Require Import Znumtheory.
Require Import vellvm_tactics.

Module MoreMem.

Export Mem.

Transparent load alloc.

Definition meminj : Type := block -> option (block * Z).

(** A memory injection defines a relation between values that is the
  identity relation, except for pointer values which are shifted
  as prescribed by the memory injection. *)

Inductive val_inject (mi: meminj): val -> val -> Prop :=
  | val_inject_int:
      forall wz i, val_inject mi (Vint wz i) (Vint wz i)
  | val_inject_float:
      forall f, val_inject mi (Vfloat f) (Vfloat f)
  | val_inject_single:
      forall f, val_inject mi (Vsingle f) (Vsingle f)
  | val_inject_ptr:
      forall b1 ofs1 b2 ofs2 delta,
      mi b1 = Some (b2, delta) ->
      ofs2 = Int.add 31 ofs1 (Int.repr 31 delta) ->
      val_inject mi (Vptr b1 ofs1) (Vptr b2 ofs2)
  | val_inject_inttoptr:
      forall i, val_inject mi (Vinttoptr i) (Vinttoptr i)
  | val_inject_undef: val_inject mi Vundef Vundef.

Hint Resolve val_inject_int val_inject_float val_inject_single val_inject_ptr val_inject_inttoptr 
             val_inject_undef.

Inductive val_list_inject (mi: meminj): list val -> list val-> Prop:= 
  | val_nil_inject :
      val_list_inject mi nil nil
  | val_cons_inject : forall v v' vl vl' , 
      val_inject mi v v' -> val_list_inject mi vl vl'->
      val_list_inject mi (v :: vl) (v' :: vl').  

Hint Resolve val_nil_inject val_cons_inject.

(* Properties of val_inject *)
Lemma val_load_result_inject:
  forall f chunk v1 v2,
  val_inject f v1 v2 ->
  val_inject f (Val.load_result chunk v1) (Val.load_result chunk v2).
Proof.
  intros. inv H; destruct chunk; simpl; try econstructor; eauto.
    destruct (eq_nat_dec _ _); try econstructor; eauto.
    destruct (eq_nat_dec _ n); try econstructor; eauto.
Qed.

Lemma val_load_result_inject_2: forall (f : block -> option (block * Z))
  (v : val) (m : memory_chunk) (Hchk : Val.has_chunk v m)
  (Hinj : val_inject f (Val.load_result m v) (Val.load_result m v)),
  val_inject f v v.
Proof.
  intros.
  destruct m, v; try inv Hchk; auto.
Qed.

Lemma val_inject__has_chunkb: forall mi v1 v2 m
  (H : val_inject mi v1 v2),
  Val.has_chunkb v1 m = Val.has_chunkb v2 m.
Proof. intros. inv H; auto. Qed.

(** Monotone evolution of a memory injection. *)

Definition inject_incr (f1 f2: meminj) : Prop :=
  forall b b' delta, f1 b = Some(b', delta) -> f2 b = Some(b', delta).

Lemma inject_incr_refl :
   forall f , inject_incr f f .
Proof. unfold inject_incr. auto. Qed.

Lemma inject_incr_trans :
  forall f1 f2 f3, 
  inject_incr f1 f2 -> inject_incr f2 f3 -> inject_incr f1 f3 .
Proof .
  unfold inject_incr; intros. eauto. 
Qed.

Lemma val_inject_incr:
  forall f1 f2 v v',
  inject_incr f1 f2 ->
  val_inject f1 v v' ->
  val_inject f2 v v'.
Proof.
  intros. inv H0; eauto.
Qed.

Lemma val_list_inject_incr:
  forall f1 f2 vl vl' ,
  inject_incr f1 f2 -> val_list_inject f1 vl vl' ->
  val_list_inject f2 vl vl'.
Proof.
  induction vl; intros; inv H0. auto.
  constructor. eapply val_inject_incr; eauto. auto.
Qed.

Hint Resolve inject_incr_refl val_inject_incr val_list_inject_incr.

Inductive memval_inject (f: meminj): memval -> memval -> Prop :=
  | memval_inject_byte:
      forall n, memval_inject f (Byte n) (Byte n)
  | memval_inject_ptr:
      forall b1 ofs1 b2 ofs2 delta n,
      f b1 = Some (b2, delta) ->
      ofs2 = Int.add 31 ofs1 (Int.repr 31 delta) ->
      memval_inject f (Fragment (Vptr b1 ofs1) Q32 n) (Fragment (Vptr b2 ofs2) Q32 n)
  | memval_inject_inttoptr:
      forall i n, memval_inject f (Fragment (Vinttoptr i) Q32 n) (Fragment (Vinttoptr i) Q32 n)
  | memval_inject_undef: memval_inject f Undef Undef.

(* Properties of memval_inject. *)
Lemma memval_inject_incr: forall f f' v1 v2, 
  memval_inject f v1 v2 -> inject_incr f f' -> memval_inject f' v1 v2.
Proof.
  intros. inv H; econstructor. rewrite (H0 _ _ _ H1). reflexivity. auto.
Qed.

Lemma inj_bytes_inject:
  forall f bl, 
    list_forall2 (memval_inject f) (inj_bytes bl) (inj_bytes bl).
Proof.
  induction bl; constructor; auto. constructor.
Qed.

Lemma repeat_Undef_inject_self:
  forall f n,
  list_forall2 (memval_inject f) (list_repeat n Undef) (list_repeat n Undef).
Proof.
  induction n; simpl; constructor; auto. constructor.
Qed.  

(* Properties of proj_bytes. *)
Lemma proj_bytes_inject_some:
  forall f vl vl',
  list_forall2 (memval_inject f) vl vl' ->
  forall bl,
  proj_bytes vl = Some bl ->
  proj_bytes vl' = Some bl.
Proof.
  induction 1; simpl. congruence.
  inv H; try congruence.

  intros.
(*  destruct (eq_nat_dec wz n0); auto.*)
  remember (proj_bytes al) as R.
  destruct R.
    inv H. rewrite (IHlist_forall2 l); auto.
    congruence.      
Qed.

Lemma proj_bytes_inject_none:
  forall f vl vl',
  list_forall2 (memval_inject f) vl vl' ->
  proj_bytes vl = None ->
  proj_bytes vl' = None.
Proof.
  induction 1; simpl. congruence.
  inv H; try congruence.

  intros.
  remember (proj_bytes al) as R.
  destruct R.
    inv H. rewrite (IHlist_forall2); auto.
Qed.

Lemma proj_bytes_not_inject:
  forall f vl vl',
  list_forall2 (memval_inject f) vl vl' ->
  proj_bytes vl = None -> proj_bytes vl' <> None -> In Undef vl.
Proof.
  induction 1; simpl; intros.
    congruence.
    inv H; try congruence; auto.
      remember (proj_bytes al) as R.
      remember (proj_bytes bl) as R'.
      destruct R; destruct R';
        try solve [inversion H1 | inversion H2 | contradict H2; auto].
        right. eapply IHlist_forall2; eauto.
        congruence.
Qed.

(* Properties of proj_pointer *)
Definition meminj_no_overlap (f: meminj) : Prop :=
  forall b1 b1' delta1 b2 b2' delta2,
  b1 <> b2 ->
  f b1 = Some (b1', delta1) ->
  f b2 = Some (b2', delta2) ->
  b1' <> b2'.

Lemma meminj_no_overlap_spec : forall f b1 b d1 b2 d2,
  meminj_no_overlap f -> f b1 = Some (b, d1) -> f b2 = Some (b, d2) ->
  b1 = b2 /\ d1 = d2.
Proof.
  intros.
  destruct (peq b1 b2); subst.
    rewrite H1 in H0.
    inv H0. split; auto.

    elimtype False. unfold meminj_no_overlap in H.
    eapply H in n; eauto.
Qed.

Lemma ptr_iptr_diff: forall b ofs i, proj_sumbool (Val.eq (Vptr b ofs) (Vinttoptr i)) = false.
Proof.
  intros. destruct (Val.eq _ _); auto; inv e.
Qed.

Lemma iptr_ptr_diff: forall b ofs i, proj_sumbool (Val.eq (Vinttoptr i) (Vptr b ofs)) = false.
Proof.
  intros. destruct (Val.eq _ _); auto; inv e.
Qed.

Lemma check_value_ptr_inject_true:
  forall f vl vl',
  list_forall2 (memval_inject f) vl vl' ->
  forall n b ofs b' delta,
  check_value n (Vptr b ofs) Q32 vl = true ->
  f b = Some(b', delta) ->
  check_value n (Vptr b' (Int.add 31 ofs (Int.repr 31 delta))) Q32 vl' = true.
Proof.
  induction 1; intros; destruct n; simpl in *; auto.
  inv H; auto.
  destruct (andb_prop _ _ H1). destruct (andb_prop _ _ H).
  destruct (andb_prop _ _ H5).
  assert (n = n0) by (apply beq_nat_true; auto).
  assert (b = b0) by (destruct (Val.eq _ _); try (inversion e; auto); inv H7).
  assert (ofs = ofs1) by (destruct (Val.eq _ _); try (inversion e; auto); inv H7).
  subst. rewrite H3 in H2; inv H2.
  unfold proj_sumbool. rewrite dec_eq_true. rewrite dec_eq_true.
  rewrite <- beq_nat_refl. simpl. eauto.

  rewrite ptr_iptr_diff in H1; inv H1.
Qed.

Definition meminj_zero_delta (f: meminj) : Prop :=
  forall b b' delta, f b = Some(b', delta) -> delta = 0.

Lemma check_value_ptr_inject_false:
  forall f vl vl',
  list_forall2 (memval_inject f) vl vl' ->
  meminj_no_overlap f ->
  meminj_zero_delta f ->
  forall n b ofs b' delta,
  check_value n (Vptr b ofs) Q32 vl = false ->
  f b = Some(b', delta) ->
  check_value n (Vptr b' (Int.add 31 ofs (Int.repr 31 delta))) Q32 vl' = false.
Proof.
  induction 1; intros; destruct n; simpl in *; auto.
  inv H; auto.
  apply andb_false_elim in H3.
  destruct H3 as [H3 | H3].
    apply andb_false_elim in H3.
    destruct H3 as [H3 | H3].
      apply andb_false_elim in H3.
      destruct H3 as [H3 | H3].
        apply andb_false_intro1.
        apply andb_false_intro1.
        apply andb_false_intro1.
        destruct (Val.eq (Vptr b ofs) (Vptr b0 ofs1)). inv H3.
  Lemma Vptr_diff: forall b ofs b0 ofs0, Vptr b ofs <> Vptr b0 ofs0 -> b <> b0 \/ ofs <> ofs0.
  Proof.
    intros.
    elim (Pos.eq_dec b b0); intro Beq;
    elim (Int.eq_dec 31 ofs ofs0); intro Oeq;
    subst; try congruence;
    tauto.
  Qed.
        exploit (Vptr_diff b ofs b0 ofs1); auto. intro Neq.
        destruct Neq; unfold meminj_no_overlap in H1.
        eapply H1 in H; eauto.
        unfold proj_sumbool.
        destruct (Val.eq (Vptr _ _) (Vptr _ _)); auto.
        inv e. congruence.
        unfold proj_sumbool. 
        destruct (Val.eq (Vptr _ _) (Vptr _ _)); auto.
        inv e.
        rewrite !Int.Z_mod_modulus_eq in H8.
        apply H2 in H5. apply H2 in H4. subst.
        rewrite Zmod_0_l in H8. rewrite <- !Zplus_0_r_reverse in H8.
        rewrite <- !Int.unsigned_repr_eq in H8.
        rewrite !Int.repr_unsigned in H8.
        unfold Int.unsigned in H8.
        apply Int.mkint_eq with (wordsize_one:=31%nat) (Px:=Int.intrange 31 ofs) (Py:=Int.intrange 31 ofs1) in H8.
        destruct ofs, ofs1.  simpl in H8. apply H in H8. inv H8.
        
        apply andb_false_intro1.
        apply andb_false_intro1.
        apply andb_false_intro2. apply H3.

        apply andb_false_intro1.
        apply andb_false_intro2. apply H3.

        apply andb_false_intro2.
        apply IHlist_forall2 with b; auto.

        rewrite ptr_iptr_diff. reflexivity.
Qed.

Lemma check_value_iptr_inject_true:
  forall f vl vl',
  list_forall2 (memval_inject f) vl vl' ->
  forall n i,
  check_value n (Vinttoptr i) Q32 vl = true ->
  check_value n (Vinttoptr i) Q32 vl' = true. 
Proof.
  induction 1; intros; destruct n; simpl in *; auto. 
  inv H; auto.
  rewrite iptr_ptr_diff in H1; inv H1.

  destruct (andb_prop _ _ H1). destruct (andb_prop _ _ H).
  apply IHlist_forall2 in H2.
  congruence.
Qed.

Lemma check_value_iptr_inject_false:
  forall f vl vl',
  list_forall2 (memval_inject f) vl vl' ->
  forall n i,
  check_value n (Vinttoptr i) Q32 vl = false ->
  check_value n (Vinttoptr i) Q32 vl' = false. 
Proof.
  induction 1; intros; destruct n; simpl in *; auto. 
  inv H; auto.
  rewrite iptr_ptr_diff; auto.

  apply andb_false_elim in H1.
  destruct H1; auto using andb_false_intro1.
    apply IHlist_forall2 in e.
    auto using andb_false_intro2.
Qed.

Lemma proj_value_inject:
  forall f vl1 vl2
  (Noover: meminj_no_overlap f)
  (Zerodelta: meminj_zero_delta f),
  list_forall2 (memval_inject f) vl1 vl2 ->
  val_inject f (proj_value Q32 vl1) (proj_value Q32 vl2).
Proof.
  intros. unfold proj_value.
  inversion H; subst; auto. inversion H0; subst; auto.
  case_eq (check_value (size_quantity_nat Q32) (Vptr b0 ofs1) Q32
        (Fragment (Vptr b0 ofs1) Q32 n :: al)); intros.
  exploit check_value_ptr_inject_true. eexact H. eauto. eauto. 
  intro. rewrite H4. econstructor; eauto.

  exploit check_value_ptr_inject_false. eexact H. eauto. eauto. eauto. eauto. 
  intro. rewrite H4. econstructor; eauto.

  inversion H; subst; auto. inversion H0; subst; auto.
  case_eq (check_value (size_quantity_nat Q32) (Vinttoptr i) Q32
        (Fragment (Vinttoptr i) Q32 n :: al)); intros.
  exploit check_value_iptr_inject_true. eexact H. eauto. eauto. 
  intro. rewrite H3. econstructor; eauto.

  exploit check_value_iptr_inject_false. eexact H. eauto. eauto. 
  intro. rewrite H3. econstructor; eauto.  
Qed.

Lemma proj_value_undef:
  forall vl, In Undef vl -> proj_value Q32 vl = Vundef.
Proof.
  intros; unfold proj_value.
  destruct vl; auto. destruct m; auto. 
  rewrite check_value_undef. auto. auto.
Qed.

(* Properties of encode/decode val *)
Theorem encode_val_inject:
  forall f v1 v2 chunk,
  val_inject f v1 v2 ->
  list_forall2 (memval_inject f) (encode_val chunk v1) (encode_val chunk v2).
Proof.
  intros. inv H; simpl.
    destruct chunk; solve [
      apply inj_bytes_inject |
      apply repeat_Undef_inject_self |
      apply repeat_Undef_inject_self].
    destruct chunk; solve [
      apply inj_bytes_inject |
      apply repeat_Undef_inject_self |
      apply repeat_Undef_inject_self].
    destruct chunk; solve [
      apply inj_bytes_inject |
      apply repeat_Undef_inject_self |
      apply repeat_Undef_inject_self].

    destruct chunk; try apply repeat_Undef_inject_self.
    destruct (eq_nat_dec _ _); subst; try apply repeat_Undef_inject_self.
      simpl; repeat econstructor; auto.

    destruct chunk; try apply repeat_Undef_inject_self.
    destruct (eq_nat_dec _ _); subst; try apply repeat_Undef_inject_self.
      unfold inj_value; simpl; repeat econstructor; auto.

    destruct chunk; try apply repeat_Undef_inject_self.
Qed.

Theorem decode_val_inject:
  forall f vl1 vl2 chunk,
  meminj_no_overlap f ->
  meminj_zero_delta f ->
  list_forall2 (memval_inject f) vl1 vl2 ->
  val_inject f (decode_val chunk vl1) (decode_val chunk vl2).
Proof.
  intros f vl1 vl2 chunk JJ JJ2 H. unfold decode_val.
  case_eq (proj_bytes vl1); intros.
    exploit proj_bytes_inject_some; eauto. intros. rewrite H1.
    destruct chunk; try constructor.

    exploit proj_bytes_inject_none; eauto. intros. rewrite H1.
    destruct chunk; auto.
    destruct (eq_nat_dec _ _); subst; auto.
      assert (H2 := H). simpl.
      apply proj_value_inject in H2; auto.
      remember (proj_value Q32 vl1) as v1.
      remember (proj_value Q32 vl2) as v2.
      inversion H2; auto.
      rewrite <- H5 in H2. rewrite <- H6 in H2. auto.
Qed.

Notation "a # b" := (Maps.PMap.get b a) (at level 1).
Notation "a ! b" := (Maps.ZMap.get b a) (at level 1).

Record mem_inj (f: meminj) (m1 m2: mem) : Prop :=
  mk_mem_inj {
    mi_access:
      forall b1 b2 delta chunk ofs p,
      f b1 = Some(b2, delta) ->
      valid_access m1 chunk b1 ofs p ->
      valid_access m2 chunk b2 (ofs + delta) p;
    mi_memval:
      forall b1 ofs b2 delta,
      f b1 = Some(b2, delta) ->
      perm m1 b1 ofs Cur Nonempty ->
      memval_inject f
        (m1.(mem_contents) # b1 ! ofs)
        (m2.(mem_contents) # b2 ! (ofs + delta))
  }.

(** Preservation of permissions *)

Lemma perm_inj:
  forall f m1 m2 b1 ofs p b2 delta,
  mem_inj f m1 m2 ->
  perm m1 b1 ofs Cur p ->
  f b1 = Some(b2, delta) ->
  perm m2 b2 (ofs + delta) Cur p.
Proof.
  intros. 
  assert (valid_access m1 (Mint 7) b1 ofs p).
  {
    split. red; intros. simpl in H2.
    replace (bytesize_chunk 7) with 1 in H2 by reflexivity.
    replace ofs0 with ofs by omega. auto.
    simpl. apply Zone_divide.
  }
  exploit mi_access; eauto. intros [A B].
  apply A. simpl; replace (bytesize_chunk 7) with 1 by reflexivity; omega. 
Qed.

(** Preservation of loads. *)

Lemma getN_inj:
  forall f m1 m2 b1 b2 delta,
  mem_inj f m1 m2 ->
  f b1 = Some(b2, delta) ->
  forall n ofs,
  range_perm m1 b1 ofs (ofs + Z_of_nat n) Cur Readable ->
  list_forall2 (memval_inject f) 
               (getN n ofs (m1.(mem_contents) # b1))
               (getN n (ofs + delta) (m2.(mem_contents) # b2)).
Proof.
  induction n; intros; simpl.
  constructor.
  rewrite inj_S in H1. 
  constructor. 
  eapply mi_memval; eauto.
  apply perm_implies with Readable.
  apply H1. omega. constructor. 
  replace (ofs + delta + 1) with ((ofs + 1) + delta) by omega.
  apply IHn. red; intros; apply H1; omega. 
Qed.

Lemma load_inj:
  forall f m1 m2 chunk b1 ofs b2 delta v1,
  meminj_no_overlap f ->
  meminj_zero_delta f ->
  mem_inj f m1 m2 ->
  load chunk m1 b1 ofs = Some v1 ->
  f b1 = Some (b2, delta) ->
  exists v2, load chunk m2 b2 (ofs + delta) = Some v2 /\ val_inject f v1 v2.
Proof.
  intros f m1 m2 chunk b1 ofs b2 delta v1 J1 J2 H H0 H1.
  exists (decode_val chunk (getN (size_chunk_nat chunk) (ofs + delta) (m2.(mem_contents) # b2))).
  split. unfold load. apply pred_dec_true.  
  eapply mi_access; eauto with mem. 
  exploit load_result; eauto. intro. rewrite H2. 
  apply decode_val_inject; auto. eapply getN_inj; auto. 
  rewrite <- size_chunk_conv. exploit load_valid_access; eauto. 
  intros [A B]. apply A.
Qed.

(** Preservation of stores. *)

Lemma setN_inj:
  forall (access: Z -> Prop) delta f vl1 vl2,
  list_forall2 (memval_inject f) vl1 vl2 ->
  forall p c1 c2,
  (forall q, access q -> memval_inject f (c1 ! q) (c2 ! (q + delta))) ->
  (forall q, access q -> memval_inject f ((setN vl1 p c1) ! q) 
                                         ((setN vl2 (p + delta) c2) ! (q + delta))).
Proof.
  induction 1; intros; simpl. 
  auto.
  replace (p + delta + 1) with ((p + 1) + delta) by omega.
  apply IHlist_forall2; auto. 
  intros. destruct (zeq q0 p). subst q0.
  rewrite !Maps.ZMap.gss. auto.
  rewrite !Maps.ZMap.gso; auto.
  intro; apply n. rewrite Z.add_cancel_r in H4. auto.
Qed.

Lemma store_mapped_inj:
  forall f chunk m1 b1 ofs v1 n1 m2 b2 delta v2,
  mem_inj f m1 m2 ->
  store chunk m1 b1 ofs v1 = Some n1 ->
  meminj_no_overlap f ->
  f b1 = Some (b2, delta) ->
  val_inject f v1 v2 ->
  exists n2,
    store chunk m2 b2 (ofs + delta) v2 = Some n2
    /\ mem_inj f n1 n2.
Proof.
  intros. inversion H. 
  assert (valid_access m2 chunk b2 (ofs + delta) Writable).
    eapply mi_access0; eauto with mem.
  destruct (valid_access_store _ _ _ _ v2 H4) as [n2 STORE]. 
  exists n2; split. eauto.
  constructor.
(* access *)
  intros.
  eapply store_valid_access_1; [apply STORE |].
  eapply mi_access0; eauto.
  eapply store_valid_access_2; [apply H0 |]. auto.
(* mem_contents *)
  intros.
  assert (perm m1 b0 ofs0 Cur Nonempty). eapply perm_store_2; eauto. 
  rewrite (store_mem_contents _ _ _ _ _ _ H0).
  rewrite (store_mem_contents _ _ _ _ _ _ STORE).
  destruct (peq b0 b1). subst b0.
  (* block = b1, block = b2 *)
  assert (b3 = b2) by congruence. subst b3.
  assert (delta0 = delta) by congruence. subst delta0.
  rewrite !Maps.PMap.gss.
  apply setN_inj with (access := fun ofs => perm m1 b1 ofs Cur Nonempty).
  apply encode_val_inject; auto. intros; eapply mi_memval0; auto. auto.
  destruct (peq b3 b2). subst b3.
  (* block <> b1, block = b2 *)
  rewrite Maps.PMap.gss.
  rewrite setN_other.
  rewrite Maps.PMap.gso; auto. eauto.
  rewrite encode_val_length. rewrite <- size_chunk_conv. intros. 
  assert (b2 <> b2).
    eapply H1; eauto. 
  congruence.
  (* block <> b1, block <> b2 *)
  repeat (rewrite Maps.PMap.gso; auto).
Qed.

Lemma store_unmapped_inj:
  forall f chunk m1 b1 ofs v1 n1 m2,
  mem_inj f m1 m2 ->
  store chunk m1 b1 ofs v1 = Some n1 ->
  f b1 = None ->
  mem_inj f n1 m2.
Proof.
  intros. inversion H.
  constructor.
(* access *)
  eauto with mem.
(* mem_contents *)
  intros. 
  rewrite (store_mem_contents _ _ _ _ _ _ H0).
  rewrite Maps.PMap.gso. eauto with mem. 
  congruence.
Qed.

Lemma store_outside_inj:
  forall f m1 m2 chunk b ofs v m2',
  mem_inj f m1 m2 ->
  (forall b' delta ofs' pk,
    f b' = Some(b, delta) ->
    perm m1 b' ofs' pk Nonempty ->
    ofs' + delta < ofs \/ ofs' + delta >= ofs + size_chunk chunk) ->
  store chunk m2 b ofs v = Some m2' ->
  mem_inj f m1 m2'.
Proof.
  intros. inversion H. constructor.
(* access *)
  eauto with mem.
(* mem_contents *)
  intros. 
  rewrite (store_mem_contents _ _ _ _ _ _ H1).
  destruct (peq b2 b). subst b2.
  rewrite Maps.PMap.gss.
  rewrite setN_outside. eauto. 
  rewrite encode_val_length. rewrite <- size_chunk_conv. 
  eapply H0; eauto.
  rewrite Maps.PMap.gso; auto.
Qed.

(** Preservation of allocations *)

Lemma alloc_right_inj:
  forall f m1 m2 lo hi b2 m2',
  mem_inj f m1 m2 ->
  alloc m2 lo hi = (m2', b2) ->
  mem_inj f m1 m2'.
Proof.
  intros. injection H0. intros NEXT MEM.
  inversion H. constructor.
(* access *)
  intros. eauto with mem. 
(* mem_contents *)
  intros.
  assert (valid_access m2 (Mint 7) b0 (ofs + delta) Nonempty).
  {
    eapply mi_access0; eauto.
    split. simpl. red; intros. replace (bytesize_chunk 7) with 1 in H3 by auto. assert (ofs0 = ofs) by omega.
    congruence.
    simpl. apply Zone_divide.
  }
  assert (valid_block m2 b0) by eauto with mem.
  rewrite <- MEM; simpl. rewrite Maps.PMap.gso. eauto with mem.
  rewrite NEXT. eauto with mem. 
Qed.

(** Preservation of frees *)

Lemma free_right_inj:
  forall f m1 m2 b lo hi m2',
  mem_inj f m1 m2 ->
  free m2 b lo hi = Some m2' ->
  (forall b1 delta ofs p,
    f b1 = Some(b, delta) -> perm m1 b1 ofs Cur p ->
    lo <= ofs + delta < hi -> False) ->
  mem_inj f m1 m2'.
Proof.
  intros. exploit free_result; eauto. intro FREE. inversion H. constructor.
(* access *)
  intros. exploit mi_access0; eauto. intros [RG AL]. split; auto.
  red; intros. eapply perm_free_1; eauto. 
  destruct (peq b2 b); auto. subst b. right.
  destruct (zlt ofs0 lo); auto. destruct (zle hi ofs0); auto.
  elimtype False. eapply H1 with (ofs := ofs0 - delta). eauto. 
  apply H3. omega. omega.
(* mem_contents *)
  intros. rewrite FREE; simpl.
  specialize (mi_memval0 _ _ _ _ H2 H3).
  assert (b=b2 /\ lo <= ofs+delta < hi \/ (b<>b2 \/ ofs+delta<lo \/ hi <= ofs+delta)).
  {
    assert (lo <= ofs+delta < hi \/ ofs + delta < lo \/ hi <= ofs + delta) by omega.
    destruct (peq b b2); tauto.
  }
  destruct H4. destruct H4. subst b2.
  specialize (H1 _ _ _ _ H2 H3). elimtype False; auto.
  auto.
Qed.

Lemma free_inj:
  forall f m1 m2 b1 b2 delta lo hi m1' m2',
  meminj_no_overlap f ->
  meminj_zero_delta f ->
  mem_inj f m1 m2 ->
  free m1 b1 lo hi = Some m1' ->
  free m2 b2 (lo+delta) (hi+delta) = Some m2' ->
  f b1 = Some (b2, delta) ->
  mem_inj f m1' m2'.
Proof.
  intros f m1 m2 b1 b2 delta lo hi m1' m2' J J' H H0 H1 H2.
  exploit free_result; eauto. 
  intro FREE. inversion H. constructor.
(* access *)
  intros.
  assert (valid_access m2 chunk b3 (ofs + delta0) p) as [RG AL] 
  by (exploit mi_access0; eauto with mem).

  split; auto.
  red; intros. eapply perm_free_1; eauto.
  destruct (peq b3 b2); auto.
    subst b2. right.
    destruct (zlt ofs0 (lo + delta)); auto.
    destruct (zle (hi + delta) ofs0); auto.
    destruct (@meminj_no_overlap_spec f b0 b3 delta0 b1 delta J H3 H2)
      as [G1 G2]; subst.
    assert (lo <= ofs0 - delta < hi) as J1.
      clear - g g0. auto with zarith.
    assert (ofs <= ofs0 - delta < ofs + size_chunk chunk) as J2.
      clear - H5. auto with zarith.
    destruct H4 as [H41 H42].
    apply H41 in J2.
    eapply perm_free_2 with (p:=p) in J1; eauto.
    apply J1 in J2; inv J2.

(* mem_contents *) 
  intros. rewrite FREE; simpl.
  assert (FREE':=H0). apply free_result in FREE'.
  rewrite FREE'; simpl.
  assert (lo <= ofs < hi \/ (ofs < lo \/ hi <= ofs)) as J1base by omega.
  assert (b0=b1 /\ lo <= ofs < hi \/ (b1<>b0 \/ ofs<lo \/ hi <= ofs)) as J1
    by (destruct (peq b0 b1); subst; try tauto ; right; left; auto).
  assert (lo+delta <= ofs+delta < hi+delta \/ (ofs+delta<lo+delta \/ hi+delta <= ofs+delta)) as J2base by omega.
  assert (b2=b3 /\ lo+delta <= ofs+delta < hi+delta \/ 
    (b2<>b3 \/ ofs+delta<lo+delta \/ hi+delta <= ofs+delta)) as J2
    by (destruct (peq b2 b3); tauto).
  destruct J1 as [J1 | J1].
    destruct J1 as [J11 J12]; subst.
    eapply perm_free_2 with (p:=Nonempty) in H0; eauto.
    apply H0 in H4; tauto.

    destruct J2 as [J2 | J2].
      destruct J2 as [J21 J22]; subst.
      destruct (@meminj_no_overlap_spec f b0 b3 delta0 b1 delta J H3 H2)
        as [G1 G2]; subst.
      assert (lo <= ofs < hi) as EQ.
        clear - J22. auto with zarith.
      clear - J1 EQ.
      destruct J1 as [J1 | J1]; try solve [congruence].
      contradict EQ; auto with zarith.

      assert (W1:=H2). apply J' in W1. subst.
      assert (W2:=H3). apply J' in W2. subst.
      eapply perm_free_3 in H4; eauto.
Qed.

Global Opaque load alloc.

Lemma free_left_nonmap_inj:
  forall f m1 m2 b lo hi m1' (Hprop: f b = None),
  mem_inj f m1 m2 ->
  Mem.free m1 b lo hi = Some m1' ->
  mem_inj f m1' m2.
Proof.
  intros. exploit Mem.free_result; eauto. intro FREE. inversion H. constructor.
(* access *)
  intros. eauto with mem.
(* mem_contents *)
  intros. rewrite FREE; simpl.
  assert (b=b1 /\ lo <= ofs < hi \/ (b<>b1 \/ ofs<lo \/ hi <= ofs))
    by (assert (lo <= ofs < hi \/ ofs<lo \/ hi <= ofs) by omega; tauto).
  destruct H3.
    destruct H3. subst b1. uniq_result.
    apply mi_memval; auto.
    eapply Mem.perm_free_3; eauto.
Qed.

End MoreMem.

