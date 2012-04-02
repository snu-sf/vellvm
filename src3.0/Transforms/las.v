Require Import vellvm.
Require Import Kildall.
Require Import ListSet.
Require Import Maps.
Require Import Lattice.
Require Import Iteration.
Require Import Maps.
Require Import opsem_props.
Require Import promotable_props.
Require Import primitives.
Require Import palloca_props.
Require Import alive_store.
Require Import id_rhs_val.
Require Import mem2reg.
Require Import program_sim.
Require Import memory_props.
Require Import trans_tactic.
Require Import top_sim.

(* We define a special las used by mem2reg that only considers local commands.
   In general, it should be extended to the las defined w.r.t domination and
   memory dependency (which we are aiming in the future work)

   The current mem2reg also does SAS eliminations before all loads are removed.
   For example,
     st v1 p; ...; st v2 p; ...
   if there are no other lds in the first ..., the first ``st v1 p'' can be
   removed.

   In practice, such a code after phiplacement may exist if the original code
   also does store to the promotable alloca.

   An alternative approach is that we only consider such elimination after all
   possible removed loads are removed, as what the paper presents. mem2reg does
   not check if there are any unremoved loads in unreachable blocks. If so,
   some stores cannot be removed. We need to let mem2reg ignore the loads of
   unreachable blocks to remove what SAS can eliminate.

   For this reason, here, we give the abstract properties that las needs to hold.
   The properties do not depend on the concrete design in mem2reg, such as
   find_init_stld, find_next_stld, ... So the proofs can still work if we change
   mem2reg. We should prove that the design in mem2reg satisfy the properties.
 *)

Definition las (lid sid: id) (v:value) (cs2:cmds) (b:block) (pinfo:PhiInfo)
  : Prop :=
blockInFdefB b (PI_f pinfo) = true /\
store_in_cmds (PI_id pinfo) cs2 = false /\
let '(block_intro _ _ cs _) := b in
exists cs1, exists cs3,
  cs =
  cs1 ++
  insn_store sid (PI_typ pinfo) v (value_id (PI_id pinfo)) (PI_align pinfo) ::
  cs2 ++
  insn_load lid (PI_typ pinfo) (value_id (PI_id pinfo)) (PI_align pinfo) ::
  cs3.

Record LASInfo (pinfo: PhiInfo) := mkLASInfo {
  LAS_lid : id;
  LAS_sid : id;
  LAS_value : value;
  LAS_tail : cmds;
  LAS_block : block;
  LAS_prop : las LAS_lid LAS_sid LAS_value LAS_tail LAS_block pinfo
}.

Ltac destruct_lasinfo :=
match goal with
| lasinfo: LASInfo _ |- _ =>
  destruct lasinfo as [LAS_lid0 LAS_sid0 LAS_value0 LAS_tail0
                       [LAS_l0 LAS_ps0 LAS_cs0 LAS_tmn0] LAS_prop0];
  destruct LAS_prop0 as 
    [LAS_BInF0 [LAS_stincmds0 [LAS_cs1 [LAS_cs3 LAS_EQ]]]]; subst; simpl
end.

Lemma lookup_LAS_lid__load: forall pinfo lasinfo
  (Huniq: uniqFdef (PI_f pinfo)),
  lookupInsnViaIDFromFdef (PI_f pinfo) (LAS_lid pinfo lasinfo) =
    ret insn_cmd
          (insn_load (LAS_lid pinfo lasinfo) (PI_typ pinfo) 
             (value_id (PI_id pinfo)) (PI_align pinfo)).
Proof.
  intros.
  destruct_lasinfo.
  match goal with 
  | H: context [?A1++?a2::?A3++?a4::?A5] |- _ =>
       rewrite_env ((A1++a2::A3)++a4::A5) in H;
       eapply IngetCmdsIDs__lookupCmdViaIDFromFdef in H; 
         eauto using in_middle
  end.
  auto.
Qed.  

Lemma LAS_lid__in_LAS_block_IDs: forall pinfo lasinfo,
  In (LAS_lid pinfo lasinfo) (getBlockIDs (LAS_block pinfo lasinfo)).
Proof.
  intros.
  destruct_lasinfo.
  apply in_or_app. right.
  rewrite getCmdsIDs_app. apply in_or_app. right.
  simpl.
  rewrite getCmdsIDs_app. apply in_or_app. right.
  simpl. auto.
Qed.

Lemma lookup_LAS_sid__store: forall pinfo lasinfo
  (Huniq: uniqFdef (PI_f pinfo)),
  lookupInsnViaIDFromFdef (PI_f pinfo) (LAS_sid pinfo lasinfo) =
    ret insn_cmd
      (insn_store (LAS_sid pinfo lasinfo) (PI_typ pinfo) 
        (LAS_value pinfo lasinfo) (value_id (PI_id pinfo)) (PI_align pinfo)).
Proof.
  intros.
  destruct_lasinfo.
  eapply IngetCmdsIDs__lookupCmdViaIDFromFdef in LAS_BInF0;eauto using in_middle.
  simpl in LAS_BInF0. auto.
Qed.  

Lemma LAS_value_is_substing: forall S m pinfo lasinfo
  (Huniq : uniqFdef (PI_f pinfo)) (HwfF : wf_fdef S m (PI_f pinfo)),
  substing_value (PI_f pinfo) (LAS_value pinfo lasinfo).
Proof.
  intros.
  assert (G:=Huniq).
  apply lookup_LAS_sid__store with (lasinfo:=lasinfo) in G.
  eapply wf_fdef__wf_insn_base in G; eauto.
  destruct G as [b HwfI].
  inv HwfI.
  unfold substing_value.
  destruct (LAS_value pinfo lasinfo) as [vid|]; auto.
  match goal with
  | H5: getInsnOperands (insn_cmd ?c) = _ |- _ =>
    apply wf_operand_list__elim with (f1:=PI_f pinfo)(b1:=b)
      (insn1:=insn_cmd c) (id1:=vid)
      in H6; try solve [
        auto |
        apply make_list_fdef_block_insn_id_spec; try solve 
          [match goal with
           | EQ: ?A = ?B |- In _ ?B => rewrite <- EQ; simpl; auto
           end]
        ]
  end.
  inv H6. 
  destruct H10 as [[block' [H10 G]] | H10]; eauto.
Qed.

Lemma LAS_value__exists: forall pinfo lasinfo s m 
  (HwfF: wf_fdef s m (PI_f pinfo)) (Huniq: uniqFdef (PI_f pinfo)),
  match LAS_value pinfo lasinfo with
  | value_id vid =>
      In vid (getArgsIDsOfFdef (PI_f pinfo)) \/
      exists instr, 
        lookupInsnViaIDFromFdef (PI_f pinfo) vid = ret instr /\
        getInsnID instr = Some vid
  | _ => True
  end.
Proof.
  intros.
  apply LAS_value_is_substing with (lasinfo:=lasinfo) in HwfF; auto.
  unfold substing_value in HwfF.
  destruct (LAS_value pinfo lasinfo); auto.
  destruct HwfF as [J | [b J]]; auto.
  right.
    eapply lookupBlockViaIDFromFdef__lookupInsnViaIDFromFdef; eauto.
Qed.

Lemma LAS_value_PI_id__dominate__LAS_sid: forall S m pinfo lasinfo
  (HwfF: wf_fdef S m (PI_f pinfo)) (Huniq: uniqFdef (PI_f pinfo))
  (Hreach: isReachableFromEntry (PI_f pinfo) (LAS_block pinfo lasinfo)) ids0
  (Hinscope: Some ids0 = inscope_of_id (PI_f pinfo) (LAS_block pinfo lasinfo) 
               (LAS_sid pinfo lasinfo)),
  value_in_scope (LAS_value pinfo lasinfo) ids0 /\
  value_in_scope (value_id (PI_id pinfo)) ids0.
Proof.
  intros.
Local Opaque inscope_of_id.
  destruct_lasinfo. simpl in *.
  unfold idDominates.
  destruct LAS_value0 as [LAS_vid0|]; simpl; split; try solve [
    auto |
    match goal with
    | HeqR : _ = inscope_of_id _ _ _, H : context [_++?c0::_++_::_] |- _ =>
      eapply cmd_operands__in_scope' with (c:=c0) in HeqR; eauto 1; 
        try solve [simpl; auto | solve_in_list]
    end
  ].
Transparent inscope_of_id.
Qed.

Lemma LAS_value__dominates__LAS_sid: forall S m pinfo lasinfo
  (HwfF: wf_fdef S m (PI_f pinfo)) (Huniq: uniqFdef (PI_f pinfo))
  (Hreach: isReachableFromEntry (PI_f pinfo) (LAS_block pinfo lasinfo)) ids0
  (Hinscope: Some ids0 = inscope_of_id (PI_f pinfo) (LAS_block pinfo lasinfo) 
               (LAS_sid pinfo lasinfo)),
  value_in_scope (LAS_value pinfo lasinfo) ids0.
Proof.
  intros.
  eapply LAS_value_PI_id__dominate__LAS_sid; eauto.
Qed.

Lemma PI_id__dominates__LAS_sid: forall S m pinfo lasinfo
  (HwfF: wf_fdef S m (PI_f pinfo)) (Huniq: uniqFdef (PI_f pinfo))
  (Hreach: isReachableFromEntry (PI_f pinfo) (LAS_block pinfo lasinfo)) ids0
  (Hinscope: Some ids0 = inscope_of_id (PI_f pinfo) (LAS_block pinfo lasinfo) 
               (LAS_sid pinfo lasinfo)),
  value_in_scope (value_id (PI_id pinfo)) ids0.
Proof.
  intros.
  eapply LAS_value_PI_id__dominate__LAS_sid; eauto.
Qed.

Lemma LAS_value_PI_id__dominate__LAS_lid: forall S m pinfo lasinfo
  (HwfF: wf_fdef S m (PI_f pinfo)) (Huniq: uniqFdef (PI_f pinfo)),
  valueDominates (PI_f pinfo) (LAS_value pinfo lasinfo) 
    (value_id (LAS_lid pinfo lasinfo)) /\
  valueDominates (PI_f pinfo) (value_id (PI_id pinfo)) 
    (value_id (LAS_lid pinfo lasinfo)).
Proof.
Local Opaque inscope_of_id.
  intros.
  assert (Hin:=@LAS_lid__in_LAS_block_IDs pinfo lasinfo).
  assert (Hlkst:=lookup_LAS_sid__store pinfo lasinfo Huniq).
  assert (Hsval:=@LAS_value__exists pinfo lasinfo _ _ HwfF Huniq).
  assert (Hidom12:=
            @LAS_value_PI_id__dominate__LAS_sid S m pinfo lasinfo HwfF 
              Huniq).
  destruct_lasinfo. simpl in *.
  unfold valueDominates, idDominates, id_in_reachable_block.
  match goal with
  | LAS_BInF0: blockInFdefB ?b0 _ = true |- _ =>
    rewrite inGetBlockIDs__lookupBlockViaIDFromFdef with (b:=b0); auto;
    assert (J:=@inscope_of_id__total (PI_f pinfo) b0 LAS_lid0);
    remember (inscope_of_id (PI_f pinfo) b0 LAS_lid0) as R;
    destruct R; try congruence;
    assert (J':=@inscope_of_id__total (PI_f pinfo) b0 LAS_sid0);
    remember (inscope_of_id (PI_f pinfo) b0 LAS_sid0) as R';
    destruct R'; try congruence;
    assert (NoDup (getBlockLocs b0)) as Hnodup; try solve [solve_NoDup]
  end.
  eapply inscope_of_id__append_cmds in HeqR; eauto.
  clear Hin.
  repeat match goal with
  | H: context [?A ++ ?b :: ?C ++ ?d :: ?E] |- _ =>
        rewrite_env ((A ++ b :: C) ++ d :: E) in H
  end. 
  destruct LAS_value0 as [LAS_vid0|]; try solve [simpl; auto];
    split; try solve [
      auto |
      intro Hreach0;
      match goal with
      | Hdom12: reachable ?f ?l0 -> _,
        Hreach0: forall _:_, Some (block_intro ?l0 ?ps ?cs ?tmn) = _ -> 
                 isReachableFromEntry ?f _ |- _ =>
        assert (isReachableFromEntry f (block_intro l0 ps cs tmn)) as Hreach; 
        eauto; simpl in Hreach;
        simpl in Hdom12; edestruct Hdom12 as [Hdom1 Hdom2]; eauto;
        apply HeqR; solve_in_list
      end
   ].
Transparent inscope_of_id.
Qed.

Lemma LAS_value__dominates__LAS_lid: forall S m pinfo lasinfo
  (HwfF: wf_fdef S m (PI_f pinfo)) (Huniq: uniqFdef (PI_f pinfo)),
  valueDominates (PI_f pinfo) (LAS_value pinfo lasinfo) 
    (value_id (LAS_lid pinfo lasinfo)).
Proof.
  intros.
  eapply LAS_value_PI_id__dominate__LAS_lid; eauto.
Qed.

Lemma PI_id__dominates__LAS_lid: forall S m pinfo lasinfo
  (HwfF: wf_fdef S m (PI_f pinfo)) (Huniq: uniqFdef (PI_f pinfo)),
   valueDominates (PI_f pinfo) (value_id (PI_id pinfo)) 
      (value_id (LAS_lid pinfo lasinfo)).
Proof.
  intros.
  eapply LAS_value_PI_id__dominate__LAS_lid; eauto.
Qed.

Lemma LAS_substable_values : forall S los nts Ps gl pinfo lasinfo
  (Huniq: uniqFdef (PI_f pinfo)) 
  (HwfF: wf_fdef S (module_intro los nts Ps) (PI_f pinfo)),
  substable_values (los,nts) gl (PI_f pinfo) (value_id (LAS_lid pinfo lasinfo))
    (LAS_value pinfo lasinfo).
Proof.
  intros.
  split. simpl. rewrite lookup_LAS_lid__load; simpl; auto.
  split. eapply LAS_value_is_substing; eauto.
  split; auto.
    eapply LAS_value__dominates__LAS_lid; eauto.
Qed.

Lemma las__alive_store: forall lid sid v cs2 b pinfo,
  las lid sid v cs2 b pinfo ->
  alive_store sid v (cs2 ++
    [insn_load lid (PI_typ pinfo) (value_id (PI_id pinfo)) (PI_align pinfo)])
    b pinfo.
Proof.
  unfold las. unfold alive_store.
  intros. destruct b.
  destruct H as [J1 [J2 [cs1 [cs3 J3]]]]; subst.
  split; auto.
  split.
    apply store_in_cmds_merge.
    split; auto.

    exists cs1. exists cs3. simpl_env. auto.
Qed.

Lemma lasinfo__stinfo: forall pinfo (lasinfo: LASInfo pinfo),
  { stinfo: StoreInfo pinfo |
    SI_id pinfo stinfo = LAS_sid pinfo lasinfo /\
    SI_value pinfo stinfo = LAS_value pinfo lasinfo /\
    SI_block pinfo stinfo = LAS_block pinfo lasinfo /\
    SI_tail pinfo stinfo =
      LAS_tail pinfo lasinfo ++
      [insn_load (LAS_lid pinfo lasinfo) (PI_typ pinfo) (value_id (PI_id pinfo))
        (PI_align pinfo)] }.
Proof.
  intros.
  destruct lasinfo. simpl.
  apply las__alive_store in LAS_prop0.
  exists (mkStoreInfo
    pinfo LAS_sid0 LAS_value0
    (LAS_tail0 ++
     [insn_load LAS_lid0 (PI_typ pinfo) (value_id (PI_id pinfo))
        (PI_align pinfo)]) LAS_block0 LAS_prop0).
  auto.
Defined.

Lemma LAS_block_spec: forall (pinfo : PhiInfo) (lasinfo : LASInfo pinfo)
  (CurCmds : list cmd) (Terminator : terminator) (l' : l) (ps' : phinodes)
  (cs' : list cmd) (Huniq: uniqFdef (PI_f pinfo))
  (Hnodup : NoDup
             (getCmdsLocs
                (cs' ++
                 insn_load (LAS_lid pinfo lasinfo) 
                   (PI_typ pinfo) (value_id (PI_id pinfo)) 
                   (PI_align pinfo) :: CurCmds)))
  (HbInF : blockInFdefB
            (block_intro l' ps'
               (cs' ++
                insn_load (LAS_lid pinfo lasinfo) (PI_typ pinfo)
                  (value_id (PI_id pinfo)) (PI_align pinfo) :: CurCmds)
               Terminator) (PI_f pinfo) = true),
  block_intro l' ps'
     (cs' ++
      insn_load (LAS_lid pinfo lasinfo) (PI_typ pinfo)
        (value_id (PI_id pinfo)) (PI_align pinfo) :: CurCmds) Terminator =
  LAS_block pinfo lasinfo.
Proof.
  intros.
  assert (In
    (LAS_lid pinfo lasinfo)
    (getBlockIDs
      (block_intro l' ps'
        (cs' ++
          insn_load (LAS_lid pinfo lasinfo) (PI_typ pinfo)
          (value_id (PI_id pinfo)) (PI_align pinfo) :: CurCmds)
        Terminator))) as Hin.
    simpl.
    rewrite getCmdsIDs_app.
    simpl.
    rewrite_env ((getPhiNodesIDs ps' ++ getCmdsIDs cs') ++
                  LAS_lid pinfo lasinfo :: getCmdsIDs CurCmds).
    apply in_middle.
  
  apply inGetBlockIDs__lookupBlockViaIDFromFdef with
    (id1:=LAS_lid pinfo lasinfo) in HbInF; auto.
  clear Hin.
  destruct lasinfo. simpl in *.
  destruct LAS_block0 as [l1 p ? t].
  destruct LAS_prop0 as [J1 [J2 [cs1 [cs3 J3]]]]. subst.
  assert (In LAS_lid0
    (getBlockIDs
      (block_intro l1 p
         (cs1 ++
          insn_store LAS_sid0 (PI_typ pinfo)
            LAS_value0 (value_id (PI_id pinfo)) (PI_align pinfo)
          :: (LAS_tail0 ++
              [insn_load LAS_lid0
                 (PI_typ pinfo) (value_id (PI_id pinfo))
                 (PI_align pinfo)] ++ cs3)) t))) as Hin.
    simpl.
    apply in_or_app. right.
    rewrite getCmdsIDs_app.
    apply in_or_app. right.
    simpl. rewrite getCmdsIDs_app.
    apply in_or_app. right. simpl. auto.
  
  eapply inGetBlockIDs__lookupBlockViaIDFromFdef with
    (id1:=LAS_lid0) in J1; eauto.
  rewrite HbInF in J1. inv J1. auto.
Qed.

Lemma lookup_LAS_lid__LAS_block: forall pinfo lasinfo
  (Huniq: uniqFdef (PI_f pinfo)),
  lookupBlockViaIDFromFdef (PI_f pinfo) (LAS_lid pinfo lasinfo) =
    ret (LAS_block pinfo lasinfo).
Proof.
  intros.
  apply inGetBlockIDs__lookupBlockViaIDFromFdef; auto.
    apply LAS_lid__in_LAS_block_IDs.
    destruct_lasinfo. auto.
Qed.

Lemma LAS_block__reachable: forall (pinfo : PhiInfo) (lasinfo : LASInfo pinfo)
  (Huniq : uniqFdef (PI_f pinfo))
  (Hreach : isReachableFromEntry (PI_f pinfo) (LAS_block pinfo lasinfo)),
  id_in_reachable_block (PI_f pinfo) (LAS_lid pinfo lasinfo).
Proof.
  unfold id_in_reachable_block. intros.
  rewrite lookup_LAS_lid__LAS_block in H; auto.
  inv H. auto.
Qed.

Lemma las__alive_store__vev_EC: forall pinfo lasinfo los nts M gl ps ec s 
  (Hwfs: wf_system s)
  (HmInS: moduleInSystemB (module_intro los nts ps) s = true)
  (Hwfpp: OpsemPP.wf_ExecutionContext (los,nts) ps ec) stinfo Hp
  (Hlas2st : exist _ stinfo Hp = lasinfo__stinfo pinfo lasinfo),
  alive_store.wf_ExecutionContext pinfo stinfo (los,nts) M gl ec ->
  vev_ExecutionContext (value_id (LAS_lid pinfo lasinfo))
    (LAS_value pinfo lasinfo) (PI_f pinfo) (los,nts) M gl ec.
Proof.
  intros. clear Hlas2st.
  destruct Hp as [J1 [J2 [J3 J4]]].
  intros.
  destruct ec. simpl in *.
  destruct CurCmds; auto.

  destruct Hwfpp as
    [Hreach [HbInF [HfInPs [_ [Hinscope [l' [ps' [cs' EQ]]]]]]]]; subst.

  remember (inscope_of_cmd CurFunction
                 (block_intro l' ps' (cs' ++ c :: CurCmds) Terminator) c) as R.
  destruct R; auto.

  assert (uniqFdef CurFunction) as Huniq.
    eapply wf_system__uniqFdef; eauto.
  assert (wf_fdef s (module_intro los nts ps) CurFunction) as HwfF.
    eapply wf_system__wf_fdef; eauto.

  assert (Hnodup:=HbInF).
  apply uniqFdef__blockInFdefB__nodup_cmds in Hnodup; auto.

  intros G1; subst.
  intro G1.
  remember (Opsem.getOperandValue (los,nts) (LAS_value pinfo lasinfo)
      Locals gl) as R.
  destruct R; auto.
  destruct (LAS_lid pinfo lasinfo == getCmdLoc c); auto.

  assert (c = insn_load (LAS_lid pinfo lasinfo) (PI_typ pinfo)
             (value_id (PI_id pinfo)) (PI_align pinfo)) as EQ.
      clear - HbInF J3 J1 J2 J4 e Huniq.
      eapply IngetCmdsIDs__lookupCmdViaIDFromFdef with (c1:=c) in HbInF; eauto
        using in_middle.
      apply lookup_LAS_lid__load with (lasinfo:=lasinfo) in Huniq; auto.
      congruence.
  subst.

  assert (block_intro l' ps'
              (cs' ++ insn_load (LAS_lid pinfo lasinfo)
                            (PI_typ pinfo) (value_id (PI_id pinfo))
                            (PI_align pinfo) :: CurCmds) Terminator =
              SI_block pinfo stinfo) as Heq.
    transitivity (LAS_block pinfo lasinfo); auto.
    eapply LAS_block_spec; eauto.

  assert (alive_store.wf_defs pinfo stinfo (los,nts) M gl Locals) as G.
    clear Hinscope Hreach.
    apply H; auto.
      clear H.
      destruct stinfo. simpl in *. subst.
      destruct (LAS_block pinfo lasinfo).
      assert (SI_alive':=SI_alive).
      destruct SI_alive' as [J1 [J2 [cs1 [cs3 J3]]]]; subst.
      inv Heq. 
      assert (
          cs' = cs1 ++
                insn_store (LAS_sid pinfo lasinfo) (PI_typ pinfo)
                  (LAS_value pinfo lasinfo) (value_id (PI_id pinfo))
                  (PI_align pinfo) :: (LAS_tail pinfo lasinfo) /\
          CurCmds = cs3
          ) as EQ.
        clear - H2 Hnodup.
        rewrite_env (
          (cs1 ++
          insn_store (LAS_sid pinfo lasinfo) (PI_typ pinfo)
            (LAS_value pinfo lasinfo) (value_id (PI_id pinfo))
            (PI_align pinfo)
          :: LAS_tail pinfo lasinfo) ++
          insn_load (LAS_lid pinfo lasinfo) (PI_typ pinfo)
              (value_id (PI_id pinfo)) (PI_align pinfo) :: cs3) in H2.
        apply NoDup_cmds_split_middle in H2; auto.

      destruct EQ; subst. clear H2.
      unfold follow_alive_store. simpl.
      intros.
      assert (cs1 = cs0 /\ cs3 = cs2) as EQ.
        clear - H Hnodup.
        rewrite_env (
          (cs1 ++
          insn_store (LAS_sid pinfo lasinfo) (PI_typ pinfo)
            (LAS_value pinfo lasinfo) (value_id (PI_id pinfo))
            (PI_align pinfo)
          :: LAS_tail pinfo lasinfo) ++
          insn_load (LAS_lid pinfo lasinfo) (PI_typ pinfo)
              (value_id (PI_id pinfo)) (PI_align pinfo) :: cs3) in H.
        rewrite_env (
          (cs0 ++
          insn_store (LAS_sid pinfo lasinfo) (PI_typ pinfo)
            (LAS_value pinfo lasinfo) (value_id (PI_id pinfo))
            (PI_align pinfo)
          :: LAS_tail pinfo lasinfo) ++
          insn_load (LAS_lid pinfo lasinfo) (PI_typ pinfo)
              (value_id (PI_id pinfo)) (PI_align pinfo) :: cs2) in H.
        apply NoDup_cmds_split_middle in H; auto.
        destruct H as [H1 H2].
        split; auto.
          apply app_inv_tail in H1; auto.

      destruct EQ; subst. clear H.
      exists (LAS_tail pinfo lasinfo).
      exists ([insn_load (LAS_lid pinfo lasinfo) (PI_typ pinfo)
                   (value_id (PI_id pinfo)) (PI_align pinfo)]).
      auto.

  simpl.
  unfold alive_store.wf_defs in G.
  assert (exists gvsa, lookupAL (GVsT DGVs) Locals (PI_id pinfo) = ret gvsa) as G2.
    rewrite Heq in *. rewrite J3 in Hreach.
    clear - Hinscope HeqR HwfF Huniq Heq HbInF Hreach.
    assert (List.In (PI_id pinfo) l0) as Hin.
      (* pid >> LAS_lid *)
      eapply PI_id__dominates__LAS_lid with (lasinfo:=lasinfo) in HwfF; eauto.
      simpl in HwfF.
      assert (forall b2 : block,
        lookupBlockViaIDFromFdef (PI_f pinfo) (LAS_lid pinfo lasinfo) =
        ret b2 -> isReachableFromEntry (PI_f pinfo) b2) as Hreach'.
        apply LAS_block__reachable; auto.
      apply_clear HwfF in Hreach'.
      unfold idDominates in Hreach'. unfold inscope_of_cmd in HeqR. simpl in HeqR.
      inv_mbind. symmetry_ctx.
      assert (b = SI_block pinfo stinfo) as HeqB.
        eapply block_eq2 with (id1:=LAS_lid pinfo lasinfo) ; eauto 1.
          solve_blockInFdefB.
          solve_in_list.

          rewrite <- Heq. simpl. apply in_or_app. right. apply in_or_app. left. 
          rewrite getCmdsLocs_app. simpl. solve_in_list.
      subst. congruence.

    eapply OpsemPP.wf_defs_elim in Hin; eauto.
    destruct Hin as [? [? [gvs1 [? [Hin ?]]]]].
    eauto.
  destruct G2 as [gvsa G2].
  rewrite J2 in G. assert (G2':=G2).
  eapply G in G2; eauto.
  exists gvsa. exists gvsa. exists g.
  split; auto.
Qed.

Lemma las__alive_store__vev_ECStack: forall pinfo lasinfo los nts M gl ps s
  (Hwfs: wf_system s) stinfo Hp 
  (HmInS: moduleInSystemB (module_intro los nts ps) s = true)
  (Hlas2st : exist _ stinfo Hp = lasinfo__stinfo pinfo lasinfo)
  ECs (Hwfpp: OpsemPP.wf_ECStack (los,nts) ps ECs),
  alive_store.wf_ECStack pinfo stinfo (los,nts) M gl ECs ->
  vev_ECStack (value_id (LAS_lid pinfo lasinfo)) (LAS_value pinfo lasinfo)
    (PI_f pinfo) (los,nts) M gl ECs.
Proof.
  induction ECs; simpl; intros; auto.
    destruct H as [J1 J2].
    destruct Hwfpp as [HwfEC [HwfStk Hwfcall]].
    split; eauto.
      eapply las__alive_store__vev_EC; eauto.
Qed.

Lemma las__alive_store__vev: forall pinfo lasinfo cfg S
  (Hwfcfg: OpsemPP.wf_Config cfg) (Hwfpp: OpsemPP.wf_State cfg S) stinfo Hp
  (Hlas2st : exist _ stinfo Hp = lasinfo__stinfo pinfo lasinfo),
  alive_store.wf_State pinfo stinfo cfg S ->
  vev_State (value_id (LAS_lid pinfo lasinfo)) (LAS_value pinfo lasinfo)
    (PI_f pinfo) cfg S.
Proof.
  intros.
  destruct cfg, S.
  destruct CurTargetData as [los nts].
  destruct Hwfcfg as [_ [Hwfg [Hwfs HmInS]]].
  destruct Hwfpp as [Hnempty Hstks].
  unfold alive_store.wf_State in H.
  simpl in H. simpl.
  eapply las__alive_store__vev_ECStack; eauto.
Qed.

Definition fdef_simulation (pinfo: PhiInfo) (lasinfo: LASInfo pinfo) f1 f2
  : Prop :=
  if (fdef_dec (PI_f pinfo) f1) then
    subst_fdef (LAS_lid pinfo lasinfo) (LAS_value pinfo lasinfo) f1 = f2
  else f1 = f2.

Definition cmds_simulation (pinfo: PhiInfo) (lasinfo: LASInfo pinfo) (f1:fdef)
  cs1 cs2 : Prop :=
  if (fdef_dec (PI_f pinfo) f1) then
    List.map (subst_cmd (LAS_lid pinfo lasinfo) (LAS_value pinfo lasinfo)) cs1
      = cs2
  else cs1 = cs2.

Definition block_simulation (pinfo: PhiInfo) (lasinfo: LASInfo pinfo) f1 b1 b2
  : Prop :=
  (if (fdef_dec (PI_f pinfo) f1) then
    subst_block (LAS_lid pinfo lasinfo) (LAS_value pinfo lasinfo) b1
  else b1) = b2.

Lemma fdef_simulation__eq_fheader: forall pinfo lasinfo f1 f2
  (H: fdef_simulation pinfo lasinfo f1 f2),
  fheaderOfFdef f1 = fheaderOfFdef f2.
Proof.
  unfold fdef_simulation.
  intros.
  destruct (fdef_dec (PI_f pinfo) f1); inv H; auto.
    destruct (PI_f pinfo) as [fh b]; simpl; auto.
Qed.

Lemma fdef_simulation__det_right: forall pinfo lasinfo f f1 f2,
  fdef_simulation pinfo lasinfo f f1 ->
  fdef_simulation pinfo lasinfo f f2 ->
  f1 = f2.
Proof.
  unfold fdef_simulation.
  intros.
  destruct_if; congruence.
Qed.

Definition Fsim (pinfo: PhiInfo) (lasinfo: LASInfo pinfo) := mkFunSim 
(fdef_simulation pinfo lasinfo)
(fdef_simulation__eq_fheader pinfo lasinfo)
(fdef_simulation__det_right pinfo lasinfo)
.

Definition products_simulation (pinfo: PhiInfo) (lasinfo: LASInfo pinfo) 
  Ps1 Ps2 : Prop :=
@TopSim.products_simulation (Fsim pinfo lasinfo) Ps1 Ps2.

Definition system_simulation (pinfo: PhiInfo) (lasinfo: LASInfo pinfo) 
  S1 S2 : Prop :=
@TopSim.system_simulation (Fsim pinfo lasinfo) S1 S2.

Definition phis_simulation (pinfo: PhiInfo) (lasinfo: LASInfo pinfo) (f1:fdef)
  ps1 ps2 : Prop :=
  if (fdef_dec (PI_f pinfo) f1) then
    List.map (subst_phi (LAS_lid pinfo lasinfo) (LAS_value pinfo lasinfo)) ps1
      = ps2
  else ps1 = ps2.

Definition tmn_simulation (pinfo: PhiInfo) (lasinfo: LASInfo pinfo) (f1:fdef)
  t t': Prop :=
(if (fdef_dec (PI_f pinfo) f1) then
  subst_tmn (LAS_lid pinfo lasinfo) (LAS_value pinfo lasinfo) t 
else t) = t'.

Definition EC_simulation (pinfo: PhiInfo) (lasinfo: LASInfo pinfo)
  (EC1 EC2:@Opsem.ExecutionContext DGVs) : Prop :=
  match (EC1, EC2) with
  | (Opsem.mkEC f1 b1 cs1 tmn1 lc1 als1,
     Opsem.mkEC f2 b2 cs2 tmn2 lc2 als2) =>
       fdef_simulation pinfo lasinfo f1 f2 /\
       tmn_simulation pinfo lasinfo f1 tmn1 tmn2 /\
       als1 = als2 /\
       block_simulation pinfo lasinfo f1 b1 b2 /\
       (exists l1, exists ps1, exists cs11,
         b1 = block_intro l1 ps1 (cs11++cs1) tmn1)
         /\
       (exists l2, exists ps2, exists cs21,
         b2 = block_intro l2 ps2 (cs21++cs2) tmn2) /\
       lc1 = lc2 /\
       cmds_simulation pinfo lasinfo f1 cs1 cs2
  end.

Fixpoint ECs_simulation (pinfo: PhiInfo) (lasinfo: LASInfo pinfo)
  (ECs1 ECs2:@Opsem.ECStack DGVs) : Prop :=
match ECs1, ECs2 with
| nil, nil => True
| EC1::ECs1', EC2::ECs2' =>
    EC_simulation pinfo lasinfo EC1 EC2 /\
    ECs_simulation pinfo lasinfo ECs1' ECs2'
| _, _ => False
end.

Definition State_simulation (pinfo: PhiInfo) (lasinfo: LASInfo pinfo)
  (Cfg1:OpsemAux.Config) (St1:Opsem.State)
  (Cfg2:OpsemAux.Config) (St2:Opsem.State) : Prop :=
let '(OpsemAux.mkCfg S1 TD1 Ps1 gl1 fs1) := Cfg1 in
let '(OpsemAux.mkCfg S2 TD2 Ps2 gl2 fs2) := Cfg2 in
match (St1, St2) with
| (Opsem.mkState ECs1 M1, Opsem.mkState ECs2 M2) =>
    TD1 = TD2 /\
    products_simulation pinfo lasinfo Ps1 Ps2 /\
    ECs_simulation pinfo lasinfo ECs1 ECs2 /\
    gl1 = gl2 /\ fs1 = fs2 /\ M1 = M2
end.

Lemma cmds_simulation_nil_inv: forall pinfo lasinfo f1 cs,
  cmds_simulation pinfo lasinfo f1 nil cs -> cs = nil.
Proof.
  unfold cmds_simulation. simpl.
  intros. destruct (fdef_dec (PI_f pinfo) f1); auto.
Qed.

Definition cmd_simulation (pinfo: PhiInfo) (lasinfo: LASInfo pinfo) (f1:fdef)
  c c': Prop :=
(if (fdef_dec (PI_f pinfo) f1) then
  subst_cmd (LAS_lid pinfo lasinfo) (LAS_value pinfo lasinfo) c
else c) = c'.

Lemma cmds_simulation_cons_inv: forall pinfo lasinfo F c1 cs2 cs',
  cmds_simulation pinfo lasinfo F (c1 :: cs2) cs' ->
  exists c1', exists cs2',
    cs' = c1' :: cs2' /\
    cmd_simulation pinfo lasinfo F c1 c1' /\
    cmds_simulation pinfo lasinfo F cs2 cs2'.
Proof.
  intros.
  unfold cmds_simulation, cmd_simulation in *.
  destruct (fdef_dec (PI_f pinfo) F); subst; simpl; eauto.
Qed.

Lemma fdef_sim__block_sim : forall pinfo lasinfo f1 f2 b1 b2 l0,
  fdef_simulation pinfo lasinfo f1 f2 ->
  lookupBlockViaLabelFromFdef f1 l0 = Some b1 ->
  lookupBlockViaLabelFromFdef f2 l0 = Some b2 ->
  block_simulation pinfo lasinfo f1 b1 b2.
Proof.
  intros.
Admitted. (* fsim *)

Lemma block_simulation_inv : forall pinfo lasinfo F l1 ps1 cs1 tmn1 l2 ps2 cs2
  tmn2,
  block_simulation pinfo lasinfo F (block_intro l1 ps1 cs1 tmn1)
    (block_intro l2 ps2 cs2 tmn2) ->
  l1 = l2 /\
  phis_simulation pinfo lasinfo F ps1 ps2 /\
  cmds_simulation pinfo lasinfo F cs1 cs2 /\
  tmn_simulation pinfo lasinfo F tmn1 tmn2.
Proof.
  intros.
  unfold block_simulation, cmds_simulation, phis_simulation, tmn_simulation in *.
  destruct (fdef_dec (PI_f pinfo) F); inv H; auto.
Qed.

Definition value_simulation (pinfo: PhiInfo) (lasinfo: LASInfo pinfo) (f1:fdef)
  v v': Prop :=
if (fdef_dec (PI_f pinfo) f1) then
  subst_value (LAS_lid pinfo lasinfo) (LAS_value pinfo lasinfo) v = v'
else v = v'.

Lemma LAS_value_doms_LAS_lid__lid_in_tmn_scope____LAS_value_inscope: forall
  (s : system) (pinfo : PhiInfo) (lasinfo : LASInfo pinfo) (tmn : terminator)
  (l1 : l) (ps1 : phinodes) (cs1 : list cmd) (l0 : list atom) m
  (HwfF : wf_fdef s m (PI_f pinfo))
  (Huniq : uniqFdef (PI_f pinfo))
  (Hreach : isReachableFromEntry (PI_f pinfo) (block_intro l1 ps1 cs1 tmn))
  (Hreach': isReachableFromEntry (PI_f pinfo) (LAS_block pinfo lasinfo))
  (HbInF : blockInFdefB (block_intro l1 ps1 cs1 tmn) (PI_f pinfo) = true)
  (HeqR : ret l0 =
          inscope_of_tmn (PI_f pinfo) (block_intro l1 ps1 cs1 tmn) tmn)
  (Hin : In (LAS_lid pinfo lasinfo) l0),
  value_in_scope (LAS_value pinfo lasinfo) l0.
Proof.
  intros.
  assert (Hdom:=HwfF).
  apply LAS_value__dominates__LAS_lid with (lasinfo:=lasinfo) in Hdom; auto.
  assert (Hsval:=@LAS_value__exists pinfo lasinfo _ _ HwfF Huniq).
  destruct (LAS_value pinfo lasinfo); auto.
  simpl in Hdom. symmetry in HeqR.
  destruct Hsval as [Hinargs | [instr [Hlkc EQ]]]; subst.
    eapply in_getArgsIDsOfFdef__inscope_of_tmn; eauto.

    assert (idDominates (PI_f pinfo) i0 (LAS_lid pinfo lasinfo)) as Hidom.
      apply Hdom. apply LAS_block__reachable; auto.
    eapply idDominates_inscope_of_tmn__inscope_of_tmn
        with (instr0:=insn_cmd 
               (insn_load (LAS_lid pinfo lasinfo) (PI_typ pinfo) 
                  (value_id (PI_id pinfo)) (PI_align pinfo))) in HeqR; eauto 1.
      symmetry. apply lookup_LAS_lid__load; auto.
Qed.

Lemma LAS_block__reachable': forall (pinfo : PhiInfo) (lasinfo : LASInfo pinfo)
  (Huniq : uniqFdef (PI_f pinfo))
  (Hreach: id_in_reachable_block (PI_f pinfo) (LAS_lid pinfo lasinfo)),
  isReachableFromEntry (PI_f pinfo) (LAS_block pinfo lasinfo).
Proof.
  intros. apply Hreach. apply lookup_LAS_lid__LAS_block; auto.
Qed.

Lemma getOperandValue_inTmnOperands_sim : forall los nts s ps gl pinfo 
  lasinfo (f : fdef) (Hwfg : wf_global (los,nts) s gl) 
  (HwfF: wf_fdef s (module_intro los nts ps) f) (Huniq: uniqFdef f)
  (tmn : terminator)
  (lc : GVMap)
  (l1 : l)
  (ps1 : phinodes)
  (cs1 : list cmd)
  (Hreach : isReachableFromEntry f (block_intro l1 ps1 cs1 tmn))
  (HbInF : blockInFdefB (block_intro l1 ps1 cs1 tmn) f = true)
  (l0 : list atom)
  (HeqR : ret l0 = inscope_of_tmn f (block_intro l1 ps1 cs1 tmn) tmn)
  (Hinscope : id_rhs_val.wf_defs (value_id (LAS_lid pinfo lasinfo))
                     (LAS_value pinfo lasinfo) (PI_f pinfo)
                     (los, nts) gl f lc l0)
  (Hinscope' : @OpsemPP.wf_defs DGVs (los, nts) f lc l0)
  (v v' : value)
  (Hvincs : valueInTmnOperands v tmn) gv gv'
  (Hget' : getOperandValue (los, nts) v' lc gl = Some gv')
  (Hvsim : value_simulation pinfo lasinfo f v v')
  (Hget : getOperandValue (los, nts) v lc gl = Some gv),
  gv = gv'.
Proof.
  intros.
  unfold value_simulation in Hvsim.
  unfold wf_defs in Hinscope.
  destruct (fdef_dec (PI_f pinfo) f); subst; try solve [uniq_result; auto].
  destruct v as [i0|]; subst; simpl in Hget', Hget, Hinscope;
    try solve [uniq_result; auto].
  destruct (id_dec i0 (LAS_lid pinfo lasinfo)); simpl in Hget'; subst;
    try solve [uniq_result; auto].
  assert (In (LAS_lid pinfo lasinfo) l0) as Hin.
    (* lid is inscope *)
    unfold inscope_of_tmn in HeqR.
    eapply terminator_operands__in_scope' in HeqR; eauto 1.
      apply valueInTmnOperands__InOps; auto.
  eapply Hinscope in Hget; eauto.
    (* lv >> lid /\ lid is inscope ==> lv is inscope *)
    assert(Hreach': isReachableFromEntry (PI_f pinfo) (LAS_block pinfo lasinfo)).
      (* lid in scope, reachable *)
      apply LAS_block__reachable'; auto.
      eapply OpsemPP.wf_defs_elim in Hinscope'; eauto. tauto.
    clear - HwfF Huniq Hreach HbInF HeqR Hin Hreach'.
    eapply LAS_value_doms_LAS_lid__lid_in_tmn_scope____LAS_value_inscope; eauto.
Qed.

Lemma LAS_value_doms_LAS_lid__lid_in_cmd_scope____LAS_value_inscope: forall
  (s : system) (pinfo : PhiInfo) (lasinfo : LASInfo pinfo) (tmn : terminator)
  (l1 : l) (ps1 : phinodes) (cs1 : list cmd) (cs : list cmd) (c : cmd) m
  (l0 : list atom) (HwfF : wf_fdef s m (PI_f pinfo)) 
  (Huniq : uniqFdef (PI_f pinfo))
  (Hreach : isReachableFromEntry (PI_f pinfo)
             (block_intro l1 ps1 (cs1 ++ c :: cs) tmn))
  (Hreach': isReachableFromEntry (PI_f pinfo) (LAS_block pinfo lasinfo))
  (HbInF : blockInFdefB (block_intro l1 ps1 (cs1 ++ c :: cs) tmn) (PI_f pinfo) =
           true)
  (HeqR : ret l0 =
         inscope_of_cmd (PI_f pinfo)
           (block_intro l1 ps1 (cs1 ++ c :: cs) tmn) c)
  (Hin : In (LAS_lid pinfo lasinfo) l0),
  value_in_scope (LAS_value pinfo lasinfo) l0.
Proof.
  intros.
  assert (Hdom:=HwfF).
  apply LAS_value__dominates__LAS_lid with (lasinfo:=lasinfo) in Hdom; auto.
  assert (Hsval:=@LAS_value__exists pinfo lasinfo _ _ HwfF Huniq).
  destruct (LAS_value pinfo lasinfo); auto.
  simpl in Hdom. symmetry in HeqR.
  destruct Hsval as [Hinargs | [instr [Hlkc EQ]]]; subst.
    eapply in_getArgsIDsOfFdef__inscope_of_cmd; eauto.

    assert (idDominates (PI_f pinfo) i0 (LAS_lid pinfo lasinfo)) as Hidom.
      apply Hdom. apply LAS_block__reachable; auto.
    eapply idDominates_inscope_of_cmd__inscope_of_cmd 
      with (c:=c)
           (instr0:=insn_cmd (insn_load (LAS_lid pinfo lasinfo) 
             (PI_typ pinfo) (value_id (PI_id pinfo)) (PI_align pinfo))) in HeqR; 
      eauto 1.
      symmetry. apply lookup_LAS_lid__load; auto.
Qed.

Lemma getOperandValue_inCmdOperands_sim : forall los nts s gl pinfo lasinfo
  ps (f : fdef) (Hwfg : wf_global (los,nts) s gl)
  (HwfF : wf_fdef s (module_intro los nts ps) f) (Huniq: uniqFdef f)
  (tmn : terminator)
  (lc : GVMap)
  (l1 : l)
  (ps1 : phinodes)
  (cs1 cs : list cmd)
  (c : cmd)
  (Hreach : isReachableFromEntry f (block_intro l1 ps1 (cs1 ++ c :: cs) tmn))
  (HbInF : blockInFdefB (block_intro l1 ps1 (cs1 ++ c :: cs) tmn) f = true)
  (l0 : list atom)
  (HeqR : ret l0 = inscope_of_cmd f (block_intro l1 ps1 (cs1 ++ c :: cs) tmn) c)
  (Hinscope : id_rhs_val.wf_defs (value_id (LAS_lid pinfo lasinfo))
                     (LAS_value pinfo lasinfo) (PI_f pinfo)
                     (los, nts) gl f lc l0)
  (Hinscope' : @OpsemPP.wf_defs DGVs (los, nts) f lc l0)
  (v v' : value)
  (Hvincs : valueInCmdOperands v c) gv gv'
  (Hget' : getOperandValue (los, nts) v' lc gl = Some gv')
  (Hvsim : value_simulation pinfo lasinfo f v v')
  (Hget : getOperandValue (los, nts) v lc gl = Some gv),
  gv = gv'.
Proof.
  intros.
  unfold value_simulation in Hvsim.
  unfold wf_defs in Hinscope.
  destruct (fdef_dec (PI_f pinfo) f); subst; try solve [uniq_result; auto].
  destruct v as [i0|]; subst; simpl in Hget', Hget, Hinscope;
    try solve [uniq_result; auto].
  destruct (id_dec i0 (LAS_lid pinfo lasinfo)); simpl in Hget'; subst;
    try solve [uniq_result; auto].
  assert (In (LAS_lid pinfo lasinfo) l0) as Hin.
    (* lid is inscope *)
    unfold inscope_of_cmd in HeqR.
    eapply cmd_operands__in_scope' in HeqR; eauto 1.
      solve_in_list.
      apply valueInCmdOperands__InOps; auto.
  eapply Hinscope in Hget; eauto.
    (* lv >> lid /\ lid is inscope ==> lv is inscope *)
    assert(Hreach': isReachableFromEntry (PI_f pinfo) (LAS_block pinfo lasinfo)).
      (* lid in scope, reachable *)
      apply LAS_block__reachable'; auto.
      eapply OpsemPP.wf_defs_elim in Hinscope'; eauto. tauto.
    clear - HwfF Huniq Hreach HbInF HeqR Hin Hreach'.
    eapply LAS_value_doms_LAS_lid__lid_in_cmd_scope____LAS_value_inscope; eauto.
Qed.

Lemma phis_simulation_nil_inv: forall pinfo lasinfo f1 ps,
  phis_simulation pinfo lasinfo f1 nil ps -> ps = nil.
Proof.
  unfold phis_simulation. simpl.
  intros. destruct (fdef_dec (PI_f pinfo) f1); auto.
Qed.

Definition phi_simulation (pinfo: PhiInfo) (lasinfo: LASInfo pinfo) (f1:fdef)
  p1 p2 : Prop :=
  if (fdef_dec (PI_f pinfo) f1) then
    subst_phi (LAS_lid pinfo lasinfo) (LAS_value pinfo lasinfo) p1 = p2
  else p1 = p2.

Lemma phis_simulation_cons_inv: forall pinfo lasinfo F p1 ps2 ps',
  phis_simulation pinfo lasinfo F (p1 :: ps2) ps' ->
  exists p1', exists ps2',
    ps' = p1' :: ps2' /\
    phi_simulation pinfo lasinfo F p1 p1' /\
    phis_simulation pinfo lasinfo F ps2 ps2'.
Proof.
  intros.
  unfold phis_simulation, phi_simulation in *.
  destruct (fdef_dec (PI_f pinfo) F); subst; simpl; eauto.
Qed.

Definition list_value_l_simulation (pinfo: PhiInfo) (lasinfo: LASInfo pinfo)
  (f1:fdef) vls vls': Prop :=
if (fdef_dec (PI_f pinfo) f1) then
  subst_list_value_l (LAS_lid pinfo lasinfo) (LAS_value pinfo lasinfo) vls = vls'
else vls = vls'.

Lemma phi_simulation_inv: forall pinfo lasinfo f1 i1 t1 vls1 i2 t2 vls2,
  phi_simulation pinfo lasinfo f1 (insn_phi i1 t1 vls1) (insn_phi i2 t2 vls2) ->
  i1 = i2 /\ t1 = t2 /\ list_value_l_simulation pinfo lasinfo f1 vls1 vls2.
Proof.
  unfold phi_simulation, list_value_l_simulation.
  intros.
  destruct (fdef_dec (PI_f pinfo) f1); inv H; auto.
Qed.

Lemma getValueViaLabelFromValuels_sim : forall l1 pinfo lasinfo f1 vls1 vls2 v
  v' (Hsim: list_value_l_simulation pinfo lasinfo f1 vls1 vls2)
  (HeqR0 : ret v = getValueViaLabelFromValuels vls1 l1)
  (HeqR' : ret v' = getValueViaLabelFromValuels vls2 l1),
  value_simulation pinfo lasinfo f1 v v'.
Proof.
  induction vls1; simpl; intros; try congruence.
    unfold list_value_l_simulation, value_simulation in *.
    destruct (fdef_dec (PI_f pinfo) f1); subst.
      simpl in HeqR'.
      destruct (l0 == l1); subst; eauto.
        congruence.

    simpl in HeqR'.
    destruct (l0 == l1); subst; try (congruence || eauto).
Qed.

Lemma getValueViaLabelFromValuels_getOperandValue_sim : forall
  los nts s gl pinfo lasinfo
  ps (f : fdef) (Hwfg : wf_global (los,nts) s gl)
  (HwfF : wf_fdef s (module_intro los nts ps) f) (HuniqF: uniqFdef f)
  (l0 : l) (lc : GVMap) (t : list atom) (l1 : l) (ps1 : phinodes)
  (cs1 : cmds) (tmn1 : terminator)
  (HeqR : ret t = inscope_of_tmn f (block_intro l1 ps1 cs1 tmn1) tmn1)
  (Hinscope : id_rhs_val.wf_defs (value_id (LAS_lid pinfo lasinfo))
                     (LAS_value pinfo lasinfo) (PI_f pinfo)
                     (los, nts) gl f lc t)
  (Hinscope' : @OpsemPP.wf_defs DGVs (los, nts) f lc t)
  (ps' : phinodes) (cs' : cmds) (tmn' : terminator)
  (i0 : id) (l2 : list_value_l) (ps2 : list phinode)
  (Hreach : isReachableFromEntry f (block_intro l0 ps' cs' tmn'))
  (HbInF : blockInFdefB (block_intro l1 ps1 cs1 tmn1) f = true)
  (Hreach' : isReachableFromEntry f (block_intro l1 ps1 cs1 tmn1))
  (v0 v0': value)
  (HeqR3 : ret v0 = getValueViaLabelFromValuels l2 l1)
  (g1 : GenericValue)
  (HeqR4 : ret g1 = getOperandValue (los,nts) v0 lc gl)
  (g2 : GVMap) (g : GenericValue) (g0 : GVMap) t1
  (H1 : wf_value_list
         (make_list_system_module_fdef_value_typ
            (map_list_value_l
               (fun (value_ : value) (_ : l) =>
                (s, module_intro los nts ps, f, value_, t1)) l2)))
  (H7 : wf_phinode f (block_intro l0 ps' cs' tmn') (insn_phi i0 t1 l2))
  (Hvsim: value_simulation pinfo lasinfo f v0 v0')
  (HeqR1 : ret g = getOperandValue (los,nts) v0' lc gl),
  g1 = g.
Proof.
  intros. symmetry_ctx.
  unfold value_simulation in Hvsim.
  destruct (fdef_dec (PI_f pinfo) f); subst; try solve [uniq_result; auto].
  destruct v0 as [vid | vc]; simpl in HeqR1, HeqR4; try congruence.
  destruct (id_dec vid (LAS_lid pinfo lasinfo)); subst; simpl in HeqR1;
    try congruence.
  assert (In (LAS_lid pinfo lasinfo) t) as Hid2InScope.
    eapply incoming_value__in_scope in H7; eauto.
  eapply Hinscope in HeqR1; eauto.
  assert(Hreach0: isReachableFromEntry (PI_f pinfo) (LAS_block pinfo lasinfo)).
    (* lid in scope, reachable *)
    apply LAS_block__reachable'; auto.
    eapply OpsemPP.wf_defs_elim in Hinscope'; eauto. tauto.
  eapply LAS_value_doms_LAS_lid__lid_in_tmn_scope____LAS_value_inscope; eauto.
Qed.

Lemma getIncomingValuesForBlockFromPHINodes_sim : forall
  los nts s gl pinfo lasinfo
  ps (f : fdef) (Hwfg : wf_global (los,nts) s gl)
  (HwfF : wf_fdef s (module_intro los nts ps) f) (HuniqF: uniqFdef f)
  l0
  (lc : GVMap)
  (t : list atom)
  l1 ps1 cs1 tmn1
  (HeqR : ret t = inscope_of_tmn f (block_intro l1 ps1 cs1 tmn1) tmn1)
  (Hinscope : id_rhs_val.wf_defs (value_id (LAS_lid pinfo lasinfo))
                     (LAS_value pinfo lasinfo) (PI_f pinfo)
                     (los, nts) gl f lc t)
  (Hinscope' : @OpsemPP.wf_defs DGVs (los, nts) f lc t)
  (ps' : phinodes)
  (cs' : cmds)
  (tmn' : terminator)
  (Hsucc : In l0 (successors_terminator tmn1))
  (Hreach : isReachableFromEntry f (block_intro l0 ps' cs' tmn'))
  (Hreach' : isReachableFromEntry f (block_intro l1 ps1 cs1 tmn1))
  (HbInF : blockInFdefB
            (block_intro l1 ps1 cs1 tmn1) f = true)
  (HwfB : wf_block s (module_intro los nts ps) f 
            (block_intro l1 ps1 cs1 tmn1))
  B1'
  (Hbsim1: block_simulation pinfo lasinfo f (block_intro l1 ps1 cs1 tmn1) B1')
  ps2
  (H8 : wf_phinodes s (module_intro los nts ps) f 
          (block_intro l0 ps' cs' tmn') ps2)
  (Hin: exists ps1, ps' = ps1 ++ ps2) RVs RVs' ps2'
  (Hpsim2: phis_simulation pinfo lasinfo f ps2 ps2')
  (Hget : @Opsem.getIncomingValuesForBlockFromPHINodes DGVs (los,nts) ps2
           (block_intro l1 ps1 cs1 tmn1) gl lc = ret RVs)
  (Hget' : @Opsem.getIncomingValuesForBlockFromPHINodes DGVs (los,nts)
             ps2' B1' gl lc = ret RVs'),
  RVs = RVs'.
Proof.
  induction ps2 as [|[i1 t1 l2]]; intros; simpl in Hget, Hget'.
    apply phis_simulation_nil_inv in Hpsim2.
    subst. simpl in Hget'. congruence.

    apply phis_simulation_cons_inv in Hpsim2.
    destruct Hpsim2 as [p1' [ps2'0 [Heq [Hpsim1 Hpsim2]]]]; subst.
    simpl in Hget'. destruct p1' as [i2 t2 l3]. 
    apply phi_simulation_inv in Hpsim1.
    destruct Hpsim1 as [Heq1 [Heq2 Hvlsim1]]; subst.
    inv_mbind'.
    destruct B1'. simpl in HeqR0.
    apply block_simulation_inv in Hbsim1.
    destruct Hbsim1 as [Heq [Hpsim1 [Hcssim1 Htsim1]]]; subst.
    simpl in HeqR3.
    eapply getValueViaLabelFromValuels_sim in Hvlsim1; eauto.
    match goal with | H8: wf_phinodes _ _ _ _ _ |- _ => inv H8 end.
    assert (g = g0) as Heq.
      match goal with | H5 : wf_insn _ _ _ _ _ |- _ => inv H5 end.
      eapply getValueViaLabelFromValuels_getOperandValue_sim with (l0:=l0);
        eauto.
    subst.
    match goal with
    | H6 : wf_phinodes _ _ _ _ _ |- _ =>
      eapply IHps2 with (RVs:=l4) in H6; eauto
    end.
      congruence.

      destruct Hin as [ps3 Hin]. subst.
      exists (ps3++[insn_phi i2 t2 l2]).
      simpl_env. auto.
Qed.

Lemma switchToNewBasicBlock_sim : forall
  los nts s gl pinfo lasinfo
  ps (f : fdef) (Hwfg : wf_global (los,nts) s gl)
  (HwfF : wf_fdef s (module_intro los nts ps) f) (HuniqF: uniqFdef f)
  l2 (lc : GVMap) (t : list atom) l1 ps1 cs1 tmn1
  (HeqR : ret t = inscope_of_tmn f (block_intro l1 ps1 cs1 tmn1) tmn1)
  (Hinscope : id_rhs_val.wf_defs (value_id (LAS_lid pinfo lasinfo))
                     (LAS_value pinfo lasinfo) (PI_f pinfo)
                     (los, nts) gl f lc t)
  (Hinscope' : @OpsemPP.wf_defs DGVs (los, nts) f lc t)
  (ps2 : phinodes) (cs2 : cmds) (tmn2 : terminator)
  (Hsucc : In l2 (successors_terminator tmn1))
  (Hreach : isReachableFromEntry f (block_intro l2 ps2 cs2 tmn2))
  (Hreach' : isReachableFromEntry f (block_intro l1 ps1 cs1 tmn1))
  (HbInF' : blockInFdefB (block_intro l2 ps2 cs2 tmn2) f = true)
  (HbInF : blockInFdefB (block_intro l1 ps1 cs1 tmn1) f = true)
  lc0 lc0'
  (Hget : @Opsem.switchToNewBasicBlock DGVs (los,nts)
    (block_intro l2 ps2 cs2 tmn2)
    (block_intro l1 ps1 cs1 tmn1) gl lc = ret lc0) B1' B2'
  (Hbsim1: block_simulation pinfo lasinfo f (block_intro l1 ps1 cs1 tmn1) B1')
  (Hbsim2: block_simulation pinfo lasinfo f (block_intro l2 ps2 cs2 tmn2) B2')
  (Hget' : @Opsem.switchToNewBasicBlock DGVs (los,nts) B2' B1' gl lc = ret lc0'),
  lc0 = lc0'.
Proof.
  intros.
  assert (HwfB : wf_block s (module_intro los nts ps) f 
           (block_intro l1 ps1 cs1 tmn1)).
    apply wf_fdef__blockInFdefB__wf_block; auto.
  assert (H8 : wf_phinodes s (module_intro los nts ps) f 
                 (block_intro l2 ps2 cs2 tmn2) ps2).
    apply wf_fdef__wf_phinodes; auto.
  unfold Opsem.switchToNewBasicBlock in *.
  inv_mbind'. app_inv. symmetry_ctx.
  assert (l3 = l0) as EQ.
    destruct B2'.
    apply block_simulation_inv in Hbsim2.
    destruct Hbsim2 as [J1 [J2 [J3 J4]]]; subst.
    eapply getIncomingValuesForBlockFromPHINodes_sim; eauto.
      exists nil. auto.
  subst. auto.
Qed.

Lemma cmds_at_block_tail_next': forall l3 ps3 cs31 c cs tmn,
  exists l1, exists ps1, exists cs11,
         block_intro l3 ps3 (cs31 ++ c :: cs) tmn =
         block_intro l1 ps1 (cs11 ++ cs) tmn.
Proof.
  intros.
  exists l3. exists ps3. exists (cs31++[c]). simpl_env. auto.
Qed.

Definition pars_simulation (pinfo: PhiInfo) (lasinfo: LASInfo pinfo) (f1:fdef)
  (ps1 ps2:params) : Prop :=
  (if (fdef_dec (PI_f pinfo) f1) then
    (List.map
      (fun p =>
       let '(t, v):=p in
       (t, subst_value (LAS_lid pinfo lasinfo) (LAS_value pinfo lasinfo) v)) ps1)
   else ps1) = ps2.

Lemma getEntryBlock__simulation: forall pinfo lasinfo f1 f2 b2,
  getEntryBlock f2 = Some b2 ->
  fdef_simulation pinfo lasinfo f1 f2 ->
  exists b1, getEntryBlock f1 = Some b1 /\ 
    block_simulation pinfo lasinfo f1 b1 b2.
Proof.
  unfold fdef_simulation.
  unfold block_simulation.
  intros.
  destruct (fdef_dec (PI_f pinfo) f1); inv H0; eauto.
    remember (PI_f pinfo) as R1.
    destruct R1 as [[? ? ? a ?] b]; simpl in *.
    destruct b; simpl in *; inv H.
    exists b. 
    split; auto.
Qed.

Lemma fdef_simulation__entry_block_simulation: forall pinfo lasinfo F1 F2 B1 B2,
  fdef_simulation pinfo lasinfo F1 F2 ->
  getEntryBlock F1 = ret B1 ->
  getEntryBlock F2 = ret B2 ->
  block_simulation pinfo lasinfo F1 B1 B2.
Proof.
  intros.
  eapply getEntryBlock__simulation in H1; eauto.
  destruct H1 as [b1 [J1 J2]].
  uniq_result. auto.
Qed.

Lemma fdef_simulation_inv: forall pinfo lasinfo fh1 fh2 bs1 bs2,
  fdef_simulation pinfo lasinfo (fdef_intro fh1 bs1) (fdef_intro fh2 bs2) ->
  fh1 = fh2 /\
  List.Forall2
    (fun b1 b2 => block_simulation pinfo lasinfo (fdef_intro fh1 bs1) b1 b2)
    bs1 bs2.
Admitted. (* fsim *)

Lemma pars_simulation_nil_inv: forall pinfo lasinfo f1 ps,
  pars_simulation pinfo lasinfo f1 nil ps -> ps = nil.
Proof.
  unfold pars_simulation. simpl.
  intros. destruct (fdef_dec (PI_f pinfo) f1); auto.
Qed.

Definition par_simulation (pinfo: PhiInfo) (lasinfo: LASInfo pinfo) (f1:fdef)
  (p p':typ * attributes * value) : Prop :=
(if (fdef_dec (PI_f pinfo) f1) then
  let '(t, v) := p in
  (t, v {[LAS_value pinfo lasinfo // LAS_lid pinfo lasinfo]})
else p) = p'.

Lemma pars_simulation_cons_inv: forall pinfo lasinfo F p1 ps2 ps',
  pars_simulation pinfo lasinfo F (p1 :: ps2) ps' ->
  exists p1', exists ps2',
    ps' = p1' :: ps2' /\
    par_simulation pinfo lasinfo F p1 p1' /\
    pars_simulation pinfo lasinfo F ps2 ps2'.
Proof.
  intros.
  unfold pars_simulation, par_simulation in *.
  destruct p1.
  destruct (fdef_dec (PI_f pinfo) F); subst; simpl; eauto.
Qed.

Lemma par_simulation__value_simulation: forall pinfo lasinfo F t1 v1 t2 v2,
  par_simulation pinfo lasinfo F (t1,v1) (t2,v2) ->
  value_simulation pinfo lasinfo F v1 v2.
Proof.
  unfold par_simulation, value_simulation.
  intros.
  destruct (fdef_dec (PI_f pinfo) F); inv H; auto.
Qed.

Lemma params2GVs_sim_aux : forall
  (s : system) pinfo lasinfo
  los nts
  (ps : list product)
  (f : fdef)
  (i0 : id)
  n c t0 v0 v p2
  (cs : list cmd)
  (tmn : terminator)
  lc (gl : GVMap) 
  (Hwfg1 : wf_global (los,nts) s gl)
  (HwfF : wf_fdef s (module_intro los nts ps) f) (Huniq: uniqFdef f)
  (l1 : l)
  (ps1 : phinodes)
  (cs1 : list cmd)
  (Hreach : isReachableFromEntry f
             (block_intro l1 ps1 (cs1 ++ insn_call i0 n c t0 v0 v p2 :: cs) tmn))
  (HbInF : blockInFdefB
            (block_intro l1 ps1 (cs1 ++ insn_call i0 n c t0 v0 v p2 :: cs) tmn) f =
          true)
  (l0 : list atom)
  (HeqR : ret l0 =
         inscope_of_cmd f
           (block_intro l1 ps1 (cs1 ++ insn_call i0 n c t0 v0 v p2 :: cs) tmn)
           (insn_call i0 n c t0 v0 v p2))
  (Hinscope : id_rhs_val.wf_defs (value_id (LAS_lid pinfo lasinfo))
           (LAS_value pinfo lasinfo) (PI_f pinfo) (los, nts) gl f lc l0)
  (Hinscope' : @OpsemPP.wf_defs DGVs (los, nts) f lc l0)
  p22 p22' gvs gvs'
  (Hex : exists p21, p2 = p21 ++ p22)
  (Hp2gv : Opsem.params2GVs (los, nts) p22 lc gl = Some gvs)
  (Hp2gv' : Opsem.params2GVs (los, nts) p22' lc gl = Some gvs')
  (Hpasim : pars_simulation pinfo lasinfo f p22 p22'),
  gvs = gvs'.
Proof.
  induction p22; simpl; intros; eauto.
    apply pars_simulation_nil_inv in Hpasim. subst.
    simpl in *. congruence.

    destruct a as [[ty0 attr0] vl0].
    destruct Hex as [p21 Hex]; subst.
    apply pars_simulation_cons_inv in Hpasim.
    destruct Hpasim as [p1' [ps2' [EQ [Hpsim' Hpasim']]]]; subst.
    simpl in *. destruct p1'.
    inv_mbind'.

    assert (g0 = g) as Heq.
      apply par_simulation__value_simulation in Hpsim'.
      eapply getOperandValue_inCmdOperands_sim in Hpsim'; eauto.
        simpl. unfold valueInParams. right.
        assert (J:=@in_split_r _ _ (p21 ++ (ty0, attr0, vl0) :: p22)
          (ty0, attr0, vl0)).
        remember (split (p21 ++ (ty0, attr0, vl0) :: p22)) as R.
        destruct R.
        simpl in J. apply J.
        apply In_middle.
    subst.
    erewrite <- IHp22 with (gvs':=l2); eauto.
      exists (p21 ++ [(ty0, attr0,vl0)]). simpl_env. auto.
Qed.

Lemma params2GVs_sim : forall
  (s : system) pinfo lasinfo
  los nts
  (ps : list product)
  (f : fdef)
  (i0 : id)
  n c t0 v0 v p2
  (cs : list cmd)
  (tmn : terminator)
  lc (gl : GVMap) 
  (Hwfg1 : wf_global (los,nts) s gl)
  (HwfF : wf_fdef s (module_intro los nts ps) f) (Huniq: uniqFdef f)
  (l1 : l)
  (ps1 : phinodes)
  (cs1 : list cmd)
  (Hreach : isReachableFromEntry f
             (block_intro l1 ps1 (cs1 ++ insn_call i0 n c t0 v0 v p2 :: cs) tmn))
  (HbInF : blockInFdefB
            (block_intro l1 ps1 (cs1 ++ insn_call i0 n c t0 v0 v p2 :: cs) tmn) f =
          true)
  (l0 : list atom)
  (HeqR : ret l0 =
         inscope_of_cmd f
           (block_intro l1 ps1 (cs1 ++ insn_call i0 n c t0 v0 v p2 :: cs) tmn)
           (insn_call i0 n c t0 v0 v p2))
  (Hinscope : id_rhs_val.wf_defs (value_id (LAS_lid pinfo lasinfo))
           (LAS_value pinfo lasinfo) (PI_f pinfo) (los, nts) gl f lc l0)
  (Hinscope' : @OpsemPP.wf_defs DGVs (los, nts) f lc l0)
  p2' gvs gvs'
  (Hp2gv : Opsem.params2GVs (los, nts) p2 lc gl = Some gvs)
  (Hp2gv' : Opsem.params2GVs (los, nts) p2' lc gl = Some gvs')
  (Hpasim : pars_simulation pinfo lasinfo f p2 p2'),
  gvs = gvs'.
Proof.
  intros.
  eapply params2GVs_sim_aux; eauto.
    exists nil. auto.
Qed.

Ltac destruct_ctx_other :=
match goal with
| Hwfcfg : OpsemPP.wf_Config _,
  Hwfpp : OpsemPP.wf_State
            {|
            OpsemAux.CurSystem := _;
            OpsemAux.CurTargetData := ?TD;
            OpsemAux.CurProducts := _;
            OpsemAux.Globals := _;
            OpsemAux.FunTable := _
             |} _,
  HwfS1 : wf_State _ _ _ _ _,
  Hsim : State_simulation _ _ _ _ ?Cfg2 ?St2 ,
  Hop2 : Opsem.sInsn _ _ _ _ |- _ =>
  destruct TD as [los nts];
  destruct Hwfcfg as [_ [Hwfg [HwfSystem HmInS]]];
  destruct Hwfpp as 
    [_ [
     [Hreach1 [HBinF1 [HFinPs1 [_ [Hinscope1 _]]]]] 
     [HwfECs Hwfcall]]
    ]; subst;
  fold (@OpsemPP.wf_ECStack DGVs) in HwfECs;
  destruct Cfg2 as [S2 TD2 Ps2 gl2 fs2];
  destruct St2 as [ECs2 M2];
  simpl in Hsim;
  destruct Hsim as [EQ1 [Hpsim [Hstksim [EQ2 [EQ3 EQ4]]]]]; subst;
  destruct ECs2 as [|[F2 B2 cs2 tmn2 lc2 als2] ECs2]; tinv Hstksim;
  destruct Hstksim as [Hecsim Hstksim];
  unfold EC_simulation in Hecsim;
  destruct Hecsim as 
      [Hfsim2 [Htsim2 [Heq2 [Hbsim2 
        [[l3 [ps3 [cs31 Heq3]]]
        [[l4 [ps4 [cs41 Heq4]]] [Hlcsim2 Hcssim2]]]]]]]; subst;
  destruct HwfS1 as [Hinscope1' HwfECs'];
  fold wf_ECStack in HwfECs';
  unfold wf_ExecutionContext in Hinscope1';
  simpl in Hinscope1'
end.

Ltac destruct_ctx_return :=
match goal with
| Hwfcfg : OpsemPP.wf_Config _,
  Hwfpp : OpsemPP.wf_State
            {|
            OpsemAux.CurSystem := _;
            OpsemAux.CurTargetData := ?TD;
            OpsemAux.CurProducts := _;
            OpsemAux.Globals := _;
            OpsemAux.FunTable := _
             |} _,
  HwfS1 : wf_State _ _ _ _ _,
  Hsim : State_simulation _ _ _ _ ?Cfg2 ?St2 ,
  Hop2 : Opsem.sInsn _ _ _ _ |- _ =>
  destruct TD as [los nts];
  destruct Hwfcfg as [_ [Hwfg [HwfSystem HmInS]]];
  destruct Hwfpp as 
    [_ [
     [Hreach1 [HBinF1 [HFinPs1 [_ [Hinscope1 _]]]]] 
     [ _ HwfCall'
     ]]
    ]; subst;
  destruct Cfg2 as [S2 TD2 Ps2 gl2 fs2];
  destruct St2 as [ECs2 M2];
  simpl in Hsim;
  destruct Hsim as [EQ1 [Hpsim [Hstksim [EQ2 [EQ3 EQ4]]]]]; subst;
  destruct ECs2 as [|[F2 B2 cs2 tmn2 lc2 als2] ECs2]; tinv Hstksim;
  destruct Hstksim as [Hecsim Hstksim];
  destruct ECs2 as [|[F3 B3 cs3 tmn3 lc3 als3] ECs2]; tinv Hstksim;
  destruct Hstksim as [Hecsim' Hstksim];
  unfold EC_simulation in Hecsim;
  destruct Hecsim as 
      [Hfsim2 [Htsim2 [Heq2 [Hbsim2 
        [Heq3 [Heq4 [Hlcsim2 Hcssim2]]]]]]]; subst;
  destruct Hecsim' as 
      [Hfsim2' [Htsim2' [Heq2' [Hbsim2' 
        [Heq3' [Heq4' [Hlcsim2' Hcssim2']]]]]]]; subst;
  destruct HwfS1 as [Hinscope1' [Hinscope2' HwfECs']];
  fold wf_ECStack in HwfECs';
  unfold wf_ExecutionContext in Hinscope1', Hinscope2';
  simpl in Hinscope1', Hinscope2';
  apply cmds_simulation_nil_inv in Hcssim2; subst;
  apply cmds_simulation_cons_inv in Hcssim2'; 
  destruct Hcssim2' as [c1' [cs3' [Heq [Hcsim2' Hcssim2']]]]; subst
end.

Definition list_sz_value_simulation (pinfo: PhiInfo) (lasinfo: LASInfo pinfo)
  (f1:fdef) vls vls': Prop :=
if (fdef_dec (PI_f pinfo) f1) then
  subst_list_value (LAS_lid pinfo lasinfo) (LAS_value pinfo lasinfo) vls = vls'
else vls = vls'.

Inductive cmd_simulation' (pinfo:PhiInfo) (lasinfo:LASInfo pinfo) (F:fdef) 
  : cmd -> cmd -> Prop :=
| cmd_simulation_bop : forall id0 bop0 sz0 v1 v2 v1' v2',
    value_simulation pinfo lasinfo F v1 v1' ->
    value_simulation pinfo lasinfo F v2 v2' ->
    cmd_simulation' pinfo lasinfo F (insn_bop id0 bop0 sz0 v1 v2)
                                    (insn_bop id0 bop0 sz0 v1' v2')
| cmd_simulation_fbop : forall id0 fbop0 fp0 v1 v2 v1' v2',
    value_simulation pinfo lasinfo F v1 v1' ->
    value_simulation pinfo lasinfo F v2 v2' ->
    cmd_simulation' pinfo lasinfo F (insn_fbop id0 fbop0 fp0 v1 v2)
                                    (insn_fbop id0 fbop0 fp0 v1' v2')
| cmd_simulation_extractvalue : forall id0 t0 v1 cs2 t1 v1',
    value_simulation pinfo lasinfo F v1 v1' ->
    cmd_simulation' pinfo lasinfo F (insn_extractvalue id0 t0 v1 cs2 t1)
                                    (insn_extractvalue id0 t0 v1' cs2 t1)
| cmd_simulation_insertvalue : forall id0 t0 v0 t1 v1 cs2 v0' v1',
    value_simulation pinfo lasinfo F v0 v0' ->
    value_simulation pinfo lasinfo F v1 v1' ->
    cmd_simulation' pinfo lasinfo F (insn_insertvalue id0 t0 v0 t1 v1 cs2)
                                    (insn_insertvalue id0 t0 v0' t1 v1' cs2)
| cmd_simulation_malloc : forall id0 t0 v0 al0 v0',
    value_simulation pinfo lasinfo F v0 v0' ->
    cmd_simulation' pinfo lasinfo F (insn_malloc id0 t0 v0 al0)
                                    (insn_malloc id0 t0 v0' al0)
| cmd_simulation_free : forall id0 t0 v0 v0',
    value_simulation pinfo lasinfo F v0 v0' ->
    cmd_simulation' pinfo lasinfo F (insn_free id0 t0 v0)
                                    (insn_free id0 t0 v0')
| cmd_simulation_alloca : forall id0 t0 v0 al0 v0',
    value_simulation pinfo lasinfo F v0 v0' ->
    cmd_simulation' pinfo lasinfo F (insn_alloca id0 t0 v0 al0)
                                    (insn_alloca id0 t0 v0' al0)
| cmd_simulation_load : forall id0 t0 v0 al0 v0',
    value_simulation pinfo lasinfo F v0 v0' ->
    cmd_simulation' pinfo lasinfo F (insn_load id0 t0 v0 al0)
                                    (insn_load id0 t0 v0' al0)
| cmd_simulation_store : forall id0 t0 v0 al0 v0' v1 v1',
    value_simulation pinfo lasinfo F v0 v0' ->
    value_simulation pinfo lasinfo F v1 v1' ->
    cmd_simulation' pinfo lasinfo F (insn_store id0 t0 v0 v1 al0)
                                    (insn_store id0 t0 v0' v1' al0)
| cmd_simulation_gep : forall id0 t0 v0 v0' vs1 vs1' t1 ib0,
    value_simulation pinfo lasinfo F v0 v0' ->
    list_sz_value_simulation pinfo lasinfo F vs1 vs1' ->
    cmd_simulation' pinfo lasinfo F (insn_gep id0 ib0 t0 v0 vs1 t1)
                                    (insn_gep id0 ib0 t0 v0' vs1' t1)
| cmd_simulation_trunc : forall id0 t0 v0 v0' t1 top0,
    value_simulation pinfo lasinfo F v0 v0' -> 
    cmd_simulation' pinfo lasinfo F (insn_trunc id0 top0 t0 v0 t1)
                                    (insn_trunc id0 top0 t0 v0' t1)
| cmd_simulation_ext : forall id0 t0 v0 v0' t1 eop0,
    value_simulation pinfo lasinfo F v0 v0' -> 
    cmd_simulation' pinfo lasinfo F (insn_ext id0 eop0 t0 v0 t1)
                                    (insn_ext id0 eop0 t0 v0' t1)
| cmd_simulation_cast : forall id0 t0 v0 v0' t1 cop0,
    value_simulation pinfo lasinfo F v0 v0' -> 
    cmd_simulation' pinfo lasinfo F (insn_cast id0 cop0 t0 v0 t1)
                                    (insn_cast id0 cop0 t0 v0' t1)
| cmd_simulation_icmp : forall id0 cond0 t0 v1 v2 v1' v2',
    value_simulation pinfo lasinfo F v1 v1' ->
    value_simulation pinfo lasinfo F v2 v2' ->
    cmd_simulation' pinfo lasinfo F (insn_icmp id0 cond0 t0 v1 v2)
                                    (insn_icmp id0 cond0 t0 v1' v2')
| cmd_simulation_fcmp : forall id0 fcond0 t0 v1 v2 v1' v2',
    value_simulation pinfo lasinfo F v1 v1' ->
    value_simulation pinfo lasinfo F v2 v2' ->
    cmd_simulation' pinfo lasinfo F (insn_fcmp id0 fcond0 t0 v1 v2)
                                    (insn_fcmp id0 fcond0 t0 v1' v2')
| cmd_simulation_select : forall id0 v0 t0 v1 v2 v1' v2' v0',
    value_simulation pinfo lasinfo F v0 v0' ->
    value_simulation pinfo lasinfo F v1 v1' ->
    value_simulation pinfo lasinfo F v2 v2' ->
    cmd_simulation' pinfo lasinfo F (insn_select id0 v0 t0 v1 v2)
                                    (insn_select id0 v0' t0 v1' v2')
| cmd_simulation_call : forall id0 nt0 ca0 t0 va0 v0 lp0 v0' lp0',
    value_simulation pinfo lasinfo F v0 v0' ->
    pars_simulation pinfo lasinfo F lp0 lp0' ->
    cmd_simulation' pinfo lasinfo F (insn_call id0 nt0 ca0 t0 va0 v0 lp0)
                                    (insn_call id0 nt0 ca0 t0 va0 v0' lp0')
.

Lemma value_simulation__refl: forall pinfo lasinfo F v,
  PI_f pinfo <> F ->
  value_simulation pinfo lasinfo F v v.
Proof.
  intros.
  unfold value_simulation.
  destruct (fdef_dec (PI_f pinfo) F); try solve [auto | congruence].
Qed.   

Lemma list_sz_value_simulation__refl: forall pinfo lasinfo F vs,
  PI_f pinfo <> F ->
  list_sz_value_simulation pinfo lasinfo F vs vs.
Proof.
  intros.
  unfold list_sz_value_simulation.
  destruct (fdef_dec (PI_f pinfo) F); try solve [auto | congruence].
Qed.

Lemma pars_simulation__refl: forall pinfo lasinfo F ps,
  PI_f pinfo <> F ->
  pars_simulation pinfo lasinfo F ps ps.
Proof.
  intros.
  unfold pars_simulation.
  destruct (fdef_dec (PI_f pinfo) F); try solve [auto | congruence].
Qed.

Lemma cmd_simulation'__refl: forall pinfo lasinfo F c,
  PI_f pinfo <> F ->
  cmd_simulation' pinfo lasinfo F c c.
Proof.
  intros.
  destruct c; constructor; 
    auto using value_simulation__refl, list_sz_value_simulation__refl,
               pars_simulation__refl.
Qed.

Lemma cmd_simulation__cmd_simulation': forall pinfo lasinfo F c c'
  (Hcsim: cmd_simulation pinfo lasinfo F c c'),
  cmd_simulation' pinfo lasinfo F c c'.
Proof.
  unfold cmd_simulation.
  intros.
  destruct (fdef_dec (PI_f pinfo) F); subst; auto using cmd_simulation'__refl.
    destruct c; simpl;
    constructor; try solve [
      unfold value_simulation, list_sz_value_simulation, pars_simulation;
      destruct (fdef_dec (PI_f pinfo) (PI_f pinfo)); try congruence; auto
    ].
Qed.

Lemma values2GVs_sim : forall los nts s gl pinfo lasinfo
  ps (f : fdef) (Hwfg : wf_global (los,nts) s gl)
  (HwfF : wf_fdef s (module_intro los nts ps) f)
  (tmn : terminator)
  (lc : GVMap)
  (l1 : l)
  (ps1 : phinodes)
  (cs1 cs : list cmd)
  (c : cmd)
  (Hreach : isReachableFromEntry f (block_intro l1 ps1 (cs1 ++ c :: cs) tmn))
  (HbInF : blockInFdefB (block_intro l1 ps1 (cs1 ++ c :: cs) tmn) f = true)
  (l0 : list atom)
  (HeqR : ret l0 = inscope_of_cmd f (block_intro l1 ps1 (cs1 ++ c :: cs) tmn) c)
  (Hinscope : id_rhs_val.wf_defs (value_id (LAS_lid pinfo lasinfo))
                     (LAS_value pinfo lasinfo) (PI_f pinfo)
                     (los, nts) gl f lc l0) t' t v id0 inbounds0 
  idxs idxs' (Heq: insn_gep id0 inbounds0 t v idxs t' = c) vidxss vidxss'
  (Hget' :  @Opsem.values2GVs DGVs (los, nts) idxs lc gl = ret vidxss)
  (Hvsim : list_sz_value_simulation pinfo lasinfo f idxs idxs')
  (Hget : @Opsem.values2GVs DGVs (los, nts) idxs' lc gl = ret vidxss'),
  vidxss = vidxss'.
Admitted. (* refer to params2GVs_sim_aux *)

Ltac las_is_sim_tac :=
  destruct_ctx_other;
  match goal with
  | Hcssim2: cmds_simulation _ _ _ _ _,
    Hop2: Opsem.sInsn _ _ _ _ |- _ =>
    apply cmds_simulation_cons_inv in Hcssim2;
    destruct Hcssim2 as [c1' [cs3' [Heq [Hcsim2 Hcssim2]]]]; subst;
    apply cmd_simulation__cmd_simulation' in Hcsim2;
    inv Hcsim2;
    inv Hop2
  end;
  repeat (split; eauto 2 using cmds_at_block_tail_next');
    f_equal;
    match goal with
    | _: moduleInSystemB (module_intro ?los ?nts ?Ps) ?S = true,
      _: InProductsB (product_fdef ?F) ?Ps = true |- _ =>
      assert (wf_fdef S (module_intro los nts Ps) F) as HwfF;
        eauto using wf_system__wf_fdef;
      assert (uniqFdef F) as Huniq; eauto using wf_system__uniqFdef;
      unfold Opsem.BOP, Opsem.FBOP, Opsem.GEP, Opsem.TRUNC, Opsem.EXT,
        Opsem.CAST, Opsem.ICMP, Opsem.FCMP in *;
      inv_mbind'; inv_mfalse; app_inv; symmetry_ctx;
      repeat match goal with
      | HeqR : Opsem.getOperandValue _ ?v1 _ _ = ret _,
        HeqR' : Opsem.getOperandValue _ ?v1' _ _ = ret _,
        Hvsim1 : value_simulation _ _ _ ?v1 ?v1'|- _ =>
        eapply getOperandValue_inCmdOperands_sim with (v':=v1') in HeqR;
          try (eauto || simpl; auto); subst;
        clear Hvsim1 HeqR'
      | HeqR : Opsem.values2GVs _ ?vs _ _ = ret _,
        HeqR' : Opsem.values2GVs _ ?vs' _ _ = ret _,
        Hvsim1 : list_sz_value_simulation _ _ _  ?vs ?vs'|- _ =>
        eapply values2GVs_sim with (idxs':=vs') in HeqR;
          try (eauto || simpl; auto); subst;
        clear Hvsim1 HeqR'
      end;
      uniq_result; auto
    end.

Lemma las_is_sim : forall pinfo lasinfo Cfg1 St1 Cfg2 St2 St2' tr2 tr1 St1'
  (Hwfpi: WF_PhiInfo pinfo) 
  (Hwfcfg: OpsemPP.wf_Config Cfg1) (Hwfpp: OpsemPP.wf_State Cfg1 St1) 
  (HwfS1: id_rhs_val.wf_State (value_id (LAS_lid pinfo lasinfo)) 
           (LAS_value pinfo lasinfo) (PI_f pinfo) Cfg1 St1)
  (Hsim: State_simulation pinfo lasinfo Cfg1 St1 Cfg2 St2)
  (Hop2: Opsem.sInsn Cfg2 St2 St2' tr2)
  (Hop1: Opsem.sInsn Cfg1 St1 St1' tr1),
  State_simulation pinfo lasinfo Cfg1 St1' Cfg2 St2' /\ tr1 = tr2.
Proof.

Local Opaque inscope_of_tmn inscope_of_cmd.

  intros.
  (sInsn_cases (destruct Hop1) Case).

Case "sReturn".

  destruct_ctx_return.

  assert (exists Result2,
    tmn2 = insn_return rid RetTy Result2 /\
    value_simulation pinfo lasinfo F Result Result2) as Hreturn.
    clear - Htsim2.
    unfold value_simulation, tmn_simulation in *.
    destruct (fdef_dec (PI_f pinfo) F); inv Htsim2; eauto.
  destruct Hreturn as [Result2 [EQ Hvsim2]]; subst.

  inv Hop2.

  match goal with
  | H0 : free_allocas ?td ?M ?las = _,
    H26 : free_allocas ?td ?M ?las = _ |- _ =>
      rewrite H0 in H26; inv H26
  end.
  wfCall_inv.

  assert (lc'' = lc''0) as EQ.
    clear - H27 H1 Hcsim2' Hvsim2 Hinscope1' HwfSystem HmInS Hreach1 HBinF1
      HFinPs1 Hwfg Hinscope1.
    unfold Opsem.returnUpdateLocals in H1, H27.
    inv_mbind'.
    destruct_cmd c1'; tinv H0.
    assert (i0 = i1 /\ n = n0 /\ t0 = t1) as EQ.
      unfold cmd_simulation in Hcsim2';
      destruct (fdef_dec (PI_f pinfo) F'); inv Hcsim2'; auto.
    destruct EQ as [Heq1 [Heq2 Heq3]]; subst.
    destruct n0; try solve [inv H0; inv H2; auto].
    inv_mbind'.
    symmetry_ctx.
    eapply getOperandValue_inTmnOperands_sim in HeqR0; eauto
      using wf_system__wf_fdef, wf_system__uniqFdef; simpl; auto.
    subst. uniq_result. auto.

  subst.
  repeat (split; eauto 2 using cmds_at_block_tail_next).

Case "sReturnVoid".
  destruct_ctx_return.

  assert (tmn2 = insn_return_void rid) as Hreturn.
    clear - Htsim2.
    unfold value_simulation, tmn_simulation in *.
    destruct (fdef_dec (PI_f pinfo) F); inv Htsim2; auto.
  subst.

  inv Hop2.

  match goal with
  | H0 : free_allocas ?td ?M ?las = _,
    H26 : free_allocas ?td ?M ?las = _ |- _ =>
      rewrite H0 in H26; inv H26
  end.
  wfCall_inv.
  repeat (split; eauto 2 using cmds_at_block_tail_next).

Case "sBranch".
Focus.

  destruct_ctx_other.
  apply cmds_simulation_nil_inv in Hcssim2; subst.

  assert (exists Cond2,
    tmn2 = insn_br bid Cond2 l1 l2 /\
    value_simulation pinfo lasinfo F Cond Cond2) as Hbr.
    clear - Htsim2.
    unfold value_simulation, tmn_simulation in *.
    destruct (fdef_dec (PI_f pinfo) F); inv Htsim2; eauto.
  destruct Hbr as [Cond2 [EQ Hvsim2]]; subst.

  inv Hop2.
  uniq_result.
  remember (inscope_of_tmn F (block_intro l3 ps3 (cs31 ++ nil)
             (insn_br bid Cond l1 l2)) (insn_br bid Cond l1 l2)) as R.
  destruct R; tinv Hinscope1'.

  assert (uniqFdef F) as HuniqF.
    eauto using wf_system__uniqFdef.
  assert (wf_fdef S (module_intro los nts Ps) F) as HwfF.
    eauto using wf_system__wf_fdef.
  assert (c = c0)as Heq.
    eapply getOperandValue_inTmnOperands_sim with (v:=Cond)(v':=Cond2);
      try solve [eauto | simpl; auto].
  subst.
  assert (block_simulation pinfo lasinfo F
           (block_intro l' ps' cs' tmn')
           (block_intro l'0 ps'0 cs'0 tmn'0)) as Hbsim.
    clear - H22 H1 Hfsim2.
    destruct (isGVZero (los, nts) c0); eauto using fdef_sim__block_sim.
  assert (Hbsim':=Hbsim).
  apply block_simulation_inv in Hbsim'.
  destruct Hbsim' as [Heq [Hpsim' [Hcssim' Htsim']]]; subst.

  assert (isReachableFromEntry F (block_intro l'0 ps' cs' tmn') /\
    In l'0 (successors_terminator (insn_br bid Cond l1 l2)) /\
    blockInFdefB (block_intro l'0 ps' cs' tmn') F = true) as J.
    symmetry in H1.
    destruct (isGVZero (los,nts) c0);
      assert (J:=H1);
      apply lookupBlockViaLabelFromFdef_inv in J; eauto;
      destruct J as [J H13']; subst;
      (repeat split; simpl; auto); try solve [
        auto | eapply reachable_successors; (eauto || simpl; auto)].
  destruct J as [Hreach' [Hsucc' HBinF1']].

  assert (lc' = lc'0) as Heq.
    eapply switchToNewBasicBlock_sim in Hbsim; eauto.
  subst.
  repeat (split; auto).
    exists l'0. exists ps'. exists nil. auto.
    exists l'0. exists ps'0. exists nil. auto.

Unfocus.

Case "sBranch_uncond".
Focus.

  destruct_ctx_other.
  apply cmds_simulation_nil_inv in Hcssim2; subst.

  assert (tmn2 = insn_br_uncond bid l0) as Hbr.
    clear - Htsim2.
    unfold value_simulation, tmn_simulation in *.
    destruct (fdef_dec (PI_f pinfo) F); inv Htsim2; eauto.
  subst.

  inv Hop2.
  uniq_result.
  remember (inscope_of_tmn F (block_intro l3 ps3 (cs31 ++ nil)
             (insn_br_uncond bid l0)) (insn_br_uncond bid l0)) as R.
  destruct R; tinv Hinscope1'.

  assert (uniqFdef F) as HuniqF.
    eauto using wf_system__uniqFdef.
  assert (wf_fdef S (module_intro los nts Ps) F) as HwfF.
    eauto using wf_system__wf_fdef.

  assert (block_simulation pinfo lasinfo F
           (block_intro l' ps' cs' tmn')
           (block_intro l'0 ps'0 cs'0 tmn'0)) as Hbsim.
    clear - H H16 Hfsim2.
    eauto using fdef_sim__block_sim.
  assert (Hbsim':=Hbsim).
  apply block_simulation_inv in Hbsim'.
  destruct Hbsim' as [Heq [Hpsim' [Hcssim' Htsim']]]; subst.

  assert (isReachableFromEntry F (block_intro l'0 ps' cs' tmn') /\
    In l'0 (successors_terminator (insn_br_uncond bid l0)) /\
    blockInFdefB (block_intro l'0 ps' cs' tmn') F = true) as J.
    symmetry in H;
    assert (J:=H);
    apply lookupBlockViaLabelFromFdef_inv in J; eauto;
    destruct J as [J H13']; subst;
    (repeat split; simpl; auto); try solve [
      auto | eapply reachable_successors; (eauto || simpl; auto)].
  destruct J as [Hreach' [Hsucc' HBinF1']].

  assert (lc' = lc'0) as Heq.
    eapply switchToNewBasicBlock_sim in Hbsim; eauto.
  subst.
  repeat (split; auto).
    exists l'0. exists ps'. exists nil. auto.
    exists l'0. exists ps'0. exists nil. auto.

Unfocus.

Case "sBop". abstract las_is_sim_tac.
Case "sFBop". abstract las_is_sim_tac.
Case "sExtractValue". abstract las_is_sim_tac.
Case "sInsertValue". abstract las_is_sim_tac.
Case "sMalloc". abstract las_is_sim_tac.
Case "sFree". abstract las_is_sim_tac.
Case "sAlloca". abstract las_is_sim_tac.
Case "sLoad". abstract las_is_sim_tac.
Case "sStore". abstract las_is_sim_tac.
Case "sGEP". abstract las_is_sim_tac.
Case "sTrunc". abstract las_is_sim_tac.
Case "sExt". abstract las_is_sim_tac.
Case "sCast". abstract las_is_sim_tac.
Case "sIcmp". abstract las_is_sim_tac.
Case "sFcmp". abstract las_is_sim_tac.
Case "sSelect". abstract las_is_sim_tac.
Case "sCall".

  destruct_ctx_other.
  assert (Hcssim2':=Hcssim2).
  apply cmds_simulation_cons_inv in Hcssim2.
  destruct Hcssim2 as [c1' [cs3' [Heq [Hcsim2 Hcssim2]]]]; subst.

  assert (exists fv', exists lp',
    c1' = insn_call rid noret0 ca rt1 va1 fv' lp' /\
    value_simulation pinfo lasinfo F fv fv' /\
    pars_simulation pinfo lasinfo F lp lp') as Hcmd.
    clear - Hcsim2.
    unfold value_simulation, cmd_simulation, pars_simulation in *.
    destruct (fdef_dec (PI_f pinfo) F); inv Hcsim2; eauto.
  destruct Hcmd as [fv' [lp' [Heq [Hvsim Hpasim]]]]; subst.

  assert (wf_fdef S (module_intro los nts Ps) F) as HwfF.
    eauto using wf_system__wf_fdef.
  assert (uniqFdef F) as Huniq. eauto using wf_system__uniqFdef.

  inv Hop2.

  SCase "SCall".

  uniq_result.

  assert (fptr = fptr0) as Heq.
    inv_mfalse; symmetry_ctx.
    eapply getOperandValue_inCmdOperands_sim with (v':=fv') in H;
      try (eauto || simpl; auto).
  subst. clear H.

  assert (Hfsim1:=Hpsim).
  eapply TopSim.lookupFdefViaPtr__simulation in Hfsim1; eauto.
  simpl in Hfsim1.
  assert (Hbsim1:=Hfsim1).
  eapply fdef_simulation__entry_block_simulation in Hbsim1; eauto.
  assert (Hbsim1':=Hbsim1).
  apply block_simulation_inv in Hbsim1'.
  destruct Hbsim1' as [Heq' [Hpsim1' [Hcsim1' Htsim1']]]; subst.
  repeat (split; eauto 4).
    exists l'0. exists ps'. exists nil. auto.
    exists l'0. exists ps'0. exists nil. auto.

    assert (gvs = gvs0) as EQ.
      inv_mfalse; symmetry_ctx.
      eapply params2GVs_sim; eauto.
    subst.
    clear - H4 H32 Hfsim1.
    apply fdef_simulation_inv in Hfsim1.
    destruct Hfsim1 as [Heq _]. inv Heq. uniq_result.
    auto.

  SCase "sExCall".

  uniq_result.
  assert (fptr = fptr0) as Heq.
    inv_mfalse; symmetry_ctx.
    eapply getOperandValue_inCmdOperands_sim with (v':=fv') in H;
      try (eauto || simpl; auto).
  subst. clear H.
  clear - H29 H1 Hpsim.

  eapply TopSim.lookupFdefViaPtr__simulation_l2r in H1; eauto.
  destruct H1 as [f2 [H1 H2]].
  apply OpsemAux.lookupExFdecViaPtr_inversion in H29.
  apply OpsemAux.lookupFdefViaPtr_inversion in H1.
  destruct H29 as [fn [J1 [J2 J3]]].
  destruct H1 as [fn' [J4 J5]].
  uniq_result.

Case "sExCall".

  destruct_ctx_other.
  assert (Hcssim2':=Hcssim2).
  apply cmds_simulation_cons_inv in Hcssim2.
  destruct Hcssim2 as [c1' [cs3' [Heq [Hcsim2 Hcssim2]]]]; subst.

  assert (exists fv', exists lp',
    c1' = insn_call rid noret0 ca rt1 va1 fv' lp' /\
    value_simulation pinfo lasinfo F fv fv' /\
    pars_simulation pinfo lasinfo F lp lp') as Hcmd.
    clear - Hcsim2.
    unfold value_simulation, cmd_simulation, pars_simulation in *.
    destruct (fdef_dec (PI_f pinfo) F); inv Hcsim2; eauto.
  destruct Hcmd as [fv' [lp' [Heq [Hvsim Hpasim]]]]; subst.

  assert (wf_fdef S (module_intro los nts Ps) F) as HwfF.
    eauto using wf_system__wf_fdef.
  assert (uniqFdef F) as Huniq. eauto using wf_system__uniqFdef.

  inv Hop2.

  SCase "SCall".

  uniq_result.

  assert (fptr = fptr0) as Heq.
    inv_mfalse; symmetry_ctx.
    eapply getOperandValue_inCmdOperands_sim with (v':=fv') in H;
      try (eauto || simpl; auto).
  subst. clear H.

  match goal with
  | Hpsim: products_simulation _ _ ?Ps ?Ps2,
    H1: OpsemAux.lookupExFdecViaPtr ?Ps _ _ = _,
    H30: OpsemAux.lookupFdefViaPtr ?Ps2 _ _ = _ |- _ =>
    clear - H30 H1 Hpsim;
    eapply TopSim.lookupExFdecViaPtr__simulation_l2r in H1; eauto;
    simpl in H1;
    apply OpsemAux.lookupExFdecViaPtr_inversion in H1;
    apply OpsemAux.lookupFdefViaPtr_inversion in H30;
    destruct H1 as [fn [J1 [J2 J3]]];
    destruct H30 as [fn' [J4 J5]]
  end.

  uniq_result.

  SCase "sExCall".

  uniq_result.

  assert (fptr = fptr0) as Heq.
    inv_mfalse; symmetry_ctx.
    eapply getOperandValue_inCmdOperands_sim with (v':=fv') in H;
      try (eauto || simpl; auto).
  subst. clear H.

  assert (Hlkdec:=Hpsim).
  eapply TopSim.lookupExFdecViaPtr__simulation_l2r in Hlkdec; eauto.

  assert (gvss = gvss0) as EQ.
    inv_mfalse; symmetry_ctx.
    eapply params2GVs_sim; eauto.
  subst.
  uniq_result.

  repeat (split; eauto 2 using cmds_at_block_tail_next').

Transparent inscope_of_tmn inscope_of_cmd.

Qed.

(* similar to phinode_bsim *)
Lemma s_genInitState__las_State_simulation: forall pinfo lasinfo S1 S2 main
  VarArgs cfg2 IS2 
  (Hssim: system_simulation pinfo lasinfo S1 S2)
  (Hinit: Opsem.s_genInitState S2 main VarArgs Mem.empty = ret (cfg2, IS2)),
  exists cfg1, exists IS1,
    Opsem.s_genInitState S1 main VarArgs Mem.empty = ret (cfg1, IS1) /\
    State_simulation pinfo lasinfo cfg1 IS1 cfg2 IS2.
Proof.
  unfold Opsem.s_genInitState.
  intros.
  inv_mbind'.
  destruct m as [los nts ps].
  inv_mbind'.
  destruct b as [l0 ps0 cs0 tmn0].
  destruct f as [[fa rt fid la va] bs].
  inv_mbind'. symmetry_ctx.
  assert (HlkF2FromS2:=HeqR).
  eapply TopSim.system_simulation__fdef_simulation_r2l in HeqR; eauto.
  destruct HeqR as [f1 [HlkF1fromS1 Hfsim]]. simpl in Hfsim.
  fill_ctxhole.
  eapply TopSim.system_simulation__getParentOfFdefFromSystem in HeqR0; eauto.
  destruct HeqR0 as [m1 [J1 J2]].
  fill_ctxhole. destruct m1 as [los1 nts1 ps1].
  destruct J2 as [J2 [J3 J4]]; subst.
  eapply TopSim.genGlobalAndInitMem_spec in HeqR1; eauto.
  destruct HeqR1 as [gl1 [fs1 [M1 [HeqR1 [EQ1 [EQ2 EQ3]]]]]]; subst.
  fill_ctxhole.
  assert (J:=HeqR2).
  eapply getEntryBlock__simulation in J; eauto.
  destruct J as [b1 [J5 J6]].
  fill_ctxhole.
  destruct b1 as [l2 ps2 cs2 tmn2].
  destruct f1 as [[fa1 rt1 fid1 la1 va1] bs1].
  assert (J:=Hfsim).
  apply fdef_simulation__eq_fheader in J.
  inv J.
  fill_ctxhole.
  match goal with
  | |- exists _:_, exists _:_, Some (?A, ?B) = _ /\ _ => exists A; exists B
  end.
  match goal with 
  | H: getParentOfFdefFromSystem _ _ = _ |- _ =>
    apply getParentOfFdefFromSystem__moduleInProductsInSystemB in H;
    destruct H as [HMinS HinPs]
  end.
  assert (J:=J6).
  apply block_simulation_inv in J.
  destruct J as [J1 [J2 [J3 J7]]]; subst.
  assert (blockInFdefB (block_intro l0 ps0 cs0 tmn0)
           (fdef_intro (fheader_intro fa rt fid la va) bs) = true) as HBinF.
    apply entryBlockInFdef; auto.
  repeat (split; auto).
    exists l0. exists ps2. exists nil. auto.
    exists l0. exists ps0. exists nil. auto.
Qed.

Lemma cmds_simulation_nil_inv' : forall (pinfo : PhiInfo) 
  (lasinfo : LASInfo pinfo) (f1 : fdef) (cs : list cmd),
  cmds_simulation pinfo lasinfo f1 cs nil -> cs = nil.
Proof.
  unfold cmds_simulation. intros.
  destruct_if; auto.
    destruct cs; inv H1; auto.
Qed.

Lemma cmds_simulation_cons_inv' : forall (pinfo : PhiInfo) 
  (lasinfo : LASInfo pinfo) (f1 : fdef) (cs : list cmd) c2 cs2,
  cmds_simulation pinfo lasinfo f1 cs (c2::cs2) -> 
  exists c1, exists cs1, 
    cs = c1::cs1 /\
    cmd_simulation pinfo lasinfo f1 c1 c2 /\
    cmds_simulation pinfo lasinfo f1 cs1 cs2.
Proof.
  unfold cmds_simulation, cmd_simulation. intros.
  destruct_if; eauto.
    destruct cs; inv H1; eauto.
Qed.

Inductive tmn_simulation' (pinfo:PhiInfo) (lasinfo:LASInfo pinfo) (F:fdef) 
  : terminator -> terminator -> Prop :=
| tmn_simulation_return : forall id0 t0 v v',
    value_simulation pinfo lasinfo F v v' ->
    tmn_simulation' pinfo lasinfo F (insn_return id0 t0 v) (insn_return id0 t0 v')
| tmn_simulation_return_void : forall id0,
    tmn_simulation' pinfo lasinfo F (insn_return_void id0) (insn_return_void id0)
| tmn_simulation_br : forall id0 v v' l1 l2,
    value_simulation pinfo lasinfo F v v' ->
    tmn_simulation' pinfo lasinfo F (insn_br id0 v l1 l2) (insn_br id0 v' l1 l2)
| tmn_simulation_br_uncond : forall id0 l0,
    tmn_simulation' pinfo lasinfo F (insn_br_uncond id0 l0) 
                                    (insn_br_uncond id0 l0)
| tmn_simulation_unreachable : forall id0,
    tmn_simulation' pinfo lasinfo F (insn_unreachable id0) 
                                    (insn_unreachable id0)
.

Lemma tmn_simulation'__refl: forall pinfo lasinfo F t,
  PI_f pinfo <> F ->
  tmn_simulation' pinfo lasinfo F t t.
Proof.
  intros.
  destruct t; constructor; auto using value_simulation__refl.
Qed.

Lemma tmn_simulation__tmn_simulation': forall pinfo lasinfo F t t'
  (Htsim: tmn_simulation pinfo lasinfo F t t'),
  tmn_simulation' pinfo lasinfo F t t'.
Proof.
  unfold tmn_simulation.
  intros.
  destruct (fdef_dec (PI_f pinfo) F); subst; auto using tmn_simulation'__refl.
    destruct t; simpl;
    constructor; try solve [
      unfold value_simulation;
      destruct (fdef_dec (PI_f pinfo) (PI_f pinfo)); try congruence; auto
    ].
Qed.

Ltac inTmnOp_isnt_stuck v H3 Hwfcfg1 Hwfpp1 :=
match type of Hwfpp1 with
| OpsemPP.wf_State 
              {|
              OpsemAux.CurSystem := _;
              OpsemAux.CurTargetData := ?td;
              OpsemAux.CurProducts := _;
              OpsemAux.Globals := ?gl;
              OpsemAux.FunTable := _ |}
    {| Opsem.ECS := {| Opsem.CurFunction := _;
                       Opsem.CurBB := ?b;
                       Opsem.CurCmds := nil;
                       Opsem.Terminator := ?tmn;
                       Opsem.Locals := ?lc;
                       Opsem.Allocas := _
                     |} :: _;
       Opsem.Mem := _ |}  =>
    let G := fresh "G" in
    let gvs := fresh "gvs" in
    assert (exists gvs, Opsem.getOperandValue td v lc gl = Some gvs) as G; 
      try solve [
        destruct H3 as [l5 [ps2 [cs21 H3]]]; subst;
        destruct Hwfcfg1 as [_ [Hwfg1 [Hwfs1 HmInS1]]];
        destruct Hwfpp1 as 
          [_ [[Hreach1 [HbInF1 [HfInPs1 [_ [Hinscope1 _]]]]] _]];
        inv_mbind;
        eapply OpsemPP.getOperandValue_inTmnOperans_isnt_stuck; eauto 1;
          simpl; auto
      ];
    destruct G as [gvs G]
end.

Ltac tmnOps_eq H3 Hwfcfg1 Hwfpp1 HwfS1 :=
      destruct H3 as [l1 [ps1 [cs11 H3]]]; subst;
      destruct Hwfcfg1 as [_ [Hwfg1 [Hwfs1 HmInS1]]];
      destruct Hwfpp1 as [_ [[Hreach1 [HbInF1 [HfInPs1 [_ [Hinscope1 _]]]]] _]];
      destruct HwfS1 as [HwfS1 _];
      unfold wf_ExecutionContext, inscope_of_ec in HwfS1;
      inv_mbind;
      eapply getOperandValue_inTmnOperands_sim; 
        eauto 2 using wf_system__wf_fdef, wf_system__uniqFdef; simpl; auto.

Lemma s_isFinialState__las_State_simulation: forall
  pinfo lasinfo cfg1 FS1 cfg2 FS2
  (Hwfcfg1: OpsemPP.wf_Config cfg1) (Hwfpp1: OpsemPP.wf_State cfg1 FS1) 
  (Hwfcfg2: OpsemPP.wf_Config cfg2) (Hwfpp2: OpsemPP.wf_State cfg2 FS2) 
  (HwfS1: id_rhs_val.wf_State (value_id (LAS_lid pinfo lasinfo)) 
           (LAS_value pinfo lasinfo) (PI_f pinfo) cfg1 FS1)
  (Hstsim : State_simulation pinfo lasinfo cfg1 FS1 cfg2 FS2),
  Opsem.s_isFinialState cfg1 FS1 = Opsem.s_isFinialState cfg2 FS2.
Proof.
  unfold Opsem.s_isFinialState.
  intros.
  destruct cfg2 as [S2 [los2 nts2] gl2 fs2].
  destruct cfg1 as [S1 [los1 nts1] gl1 fs1].
  destruct FS1 as [[|[? ? cs1 ? ?] ES1]]; 
  destruct FS2 as [[|[? ? cs2 ? ?] ES2]]; try solve [
    auto |
    destruct Hstsim as [X [? [Hstsim [? [? ?]]]]]; subst; inv Hstsim
  ].
  destruct Hstsim as [X [? [Hstsim [? [? ?]]]]]; subst.
  inv X. simpl.
  destruct Hstsim as [Hstsim Hstsim'].
  fold ECs_simulation in Hstsim'.
  destruct Hstsim as [? [Htmn [? [? [? [? [? Hstsim]]]]]]]; subst.
  destruct cs1, cs2; try solve [
    auto |
    apply cmds_simulation_nil_inv in Hstsim; try congruence |
    apply cmds_simulation_nil_inv' in Hstsim; try congruence
  ].
  apply tmn_simulation__tmn_simulation' in Htmn.
  inv Htmn; auto.
    destruct ES1, ES2; try solve [auto | inv Hstsim'].
      inTmnOp_isnt_stuck v H3 Hwfcfg1 Hwfpp1.
      inTmnOp_isnt_stuck v' H4 Hwfcfg2 Hwfpp2.
      rewrite G. rewrite G0.
      f_equal.
      tmnOps_eq H3 Hwfcfg1 Hwfpp1 HwfS1.

    destruct ES1, ES2; try solve [auto | inv Hstsim'].
Qed.

Ltac undefined_state__State_simulation_r2l_tac1 :=
  match goal with
  | Hstsim: State_simulation _ _ _ ?St1 _ ?St2 |- _ =>
    destruct St2 as [[|[? ? [|CurCmds] [] ?] [|[]]] ?]; try tauto;
    destruct CurCmds; try tauto;
    destruct St1 as [ECS ?];
    destruct Hstsim as [X [? [Hstsim [? [? ?]]]]]; subst;
    inv X;
    destruct ECS as [|[] ECS]; try tauto;
    destruct Hstsim as [Hstsim Hstsim'];
    destruct ECS as [|[] ECS]; try tauto;
    destruct Hstsim as [? [Htmn [? [? [? [? [? Hstsim]]]]]]]; subst;
    destruct Hstsim' as [Hstsim' _];
    destruct Hstsim' as [? [? [? [? [? [? [? Hstsim']]]]]]]; subst;
   simpl
  end.

Ltac undefined_state__State_simulation_r2l_tac3 :=
  match goal with
  | Hstsim: State_simulation _ _ _ ?St1 _ ?St2 |- _ =>
    destruct St2 as [[|[? [? ? ? tmn] CurCmds tmn' ?] ?] ?]; try tauto;
    destruct tmn; try tauto;
    destruct CurCmds; try tauto;
    destruct tmn'; try tauto;
    destruct St1 as [ECS ?];
    destruct Hstsim as [X [? [Hstsim [? [? H3]]]]]; subst;
    inv X;
    destruct ECS as [|[] ECS]; try tauto;
    destruct Hstsim as [Hstsim _];
    destruct Hstsim as [? [Htmn [? [? [? [? [? Hstsim]]]]]]]; subst;
    destruct H3 as [l5 [ps5 [cs5 EQ]]]; subst
  end.

Ltac undefined_state__State_simulation_r2l_tac41 :=
  match goal with
  | Hstsim: State_simulation _ _ _ ?St1 ?cfg2 ?St2 |- _ =>
    destruct St1 as [ECS ?];
    destruct Hstsim as [X [? [Hstsim [? [? ?]]]]]; subst;
    inv X;
    destruct ECS as [|[? ? ? ? Locals0] ECS]; try tauto;
    destruct Hstsim as [Hstsim _];
    destruct Hstsim as [? [? [? [? [H4 [H5 [? Hstsim]]]]]]]; subst
  end. 

Ltac undefined_state__la_State_simulation_r2l_tac42 := 
repeat match goal with
| Hwfcfg1: OpsemPP.wf_Config ?cfg1, Hwfpp1: OpsemPP.wf_State ?cfg1 ?St1, 
  HwfS1: wf_State _ _ _ ?cfg1 ?St1, 
  Hvsim: value_simulation _ _ _ ?v0 ?v,
  _: ret ?gn = Opsem.getOperandValue ?td ?v ?Locals ?fs2,
  _: block_simulation _ _ _ ?b _,
  H4: exists _:_, exists _:_, exists _:_, ?b = _ |- _ =>
    let G := fresh "G" in
    let gvs := fresh "gvs" in
    assert (exists gvs, Opsem.getOperandValue td
       v0 Locals fs2 = Some gvs) as G; try solve [
      destruct H4 as [l5 [ps2 [cs21 H4]]]; subst;
      destruct Hwfcfg1 as [_ [Hwfg1 [Hwfs1 HmInS1]]];
      destruct Hwfpp1 as [_ [[Hreach1 [HbInF1 [HfInPs1 [_ [Hinscope1 _]]]]] _]];
      inv_mbind;
      eapply OpsemPP.getOperandValue_inCmdOps_isnt_stuck; eauto 1; simpl; auto
    ];
    destruct G as [gvs G];
    assert (gvs = gn) as EQ; try solve [
      destruct H4 as [l1 [ps1 [cs11 H4]]]; subst;
      destruct Hwfcfg1 as [_ [Hwfg1 [Hwfs1 HmInS1]]];
      destruct Hwfpp1 as [_ [[Hreach1 [HbInF1 [HfInPs1 [_ [Hinscope1 _]]]]] _]];
      destruct HwfS1 as [HwfS1 _];
      unfold wf_ExecutionContext, inscope_of_ec in HwfS1;
      inv_mbind;
      eapply getOperandValue_inCmdOperands_sim; 
        eauto 2 using wf_system__wf_fdef, wf_system__uniqFdef; simpl; auto
    ];
    subst;
    clear Hvsim
end.

Ltac undefined_state__la_State_simulation_r2l_tac43 := 
      match goal with
      | Hstsim: cmds_simulation _ _ _ _ (_::_) |- _ =>
      apply cmds_simulation_cons_inv' in Hstsim; subst;
      destruct Hstsim as [c1' [cs2' [J1 [J2 J3]]]]; subst;
      apply cmd_simulation__cmd_simulation' in J2;
      inv J2;
      undefined_state__la_State_simulation_r2l_tac42
     end.

Lemma undefined_state__las_State_simulation_r2l: forall pinfo lasinfo cfg1 St1 
  cfg2 St2 (Hstsim : State_simulation pinfo lasinfo cfg1 St1 cfg2 St2)
  (Hwfcfg1: OpsemPP.wf_Config cfg1) (Hwfpp1: OpsemPP.wf_State cfg1 St1) 
  (HwfS1: id_rhs_val.wf_State (value_id (LAS_lid pinfo lasinfo)) 
           (LAS_value pinfo lasinfo) (PI_f pinfo) cfg1 St1)
  (Hundef: OpsemPP.undefined_state cfg2 St2), OpsemPP.undefined_state cfg1 St1.
Proof.
  intros.
  unfold OpsemPP.undefined_state in Hundef.
  destruct cfg2 as [S2 [los2 nts2] gl2 fs2].
  destruct cfg1 as [S1 [los1 nts1] gl1 fs1].
  repeat match goal with
  | Hundef : _ \/ _ |- _ => destruct Hundef as [Hundef | Hundef]
  end.
  Case "1".

    undefined_state__State_simulation_r2l_tac1.
    apply cmds_simulation_nil_inv' in Hstsim; subst.
    apply cmds_simulation_cons_inv' in Hstsim'.
    destruct Hstsim' as [c1' [cs1' [J1 [J2 J3]]]]; subst.
    left. 
    unfold tmn_simulation in Htmn. 
    destruct_if; subst; simpl; auto.
    match goal with
    | H11: subst_tmn _ _ ?tmn = insn_return _ _ _ |- _ => 
      destruct tmn; inv H11; auto
    end.

  Case "2".
    undefined_state__State_simulation_r2l_tac1.
    apply cmds_simulation_nil_inv' in Hstsim; subst.
    apply cmds_simulation_cons_inv' in Hstsim'.
    destruct Hstsim' as [c1' [cs1' [J1 [J2 J3]]]]; subst.
    right. left.
    assert (getCallerReturnID c = getCallerReturnID c1') as EQ.
      unfold cmd_simulation in J2. subst. clear.
      destruct_if; auto.
      destruct c1'; auto.
    rewrite <- EQ.
    clear - Htmn Hundef.
    unfold tmn_simulation in Htmn. 
    destruct (fdef_dec (PI_f pinfo) CurFunction1); subst; simpl; auto.
    match goal with
    | H11: subst_tmn _ _ ?tmn = insn_return_void _ |- _ => 
      destruct tmn; inv H11; auto
    end.

  Case "3".

    undefined_state__State_simulation_r2l_tac3.
    apply cmds_simulation_nil_inv' in Hstsim. subst.
    right. right. left.
    simpl. 
    unfold tmn_simulation in Htmn. 
    destruct_if; subst; simpl; auto.
    match goal with
    | H11: subst_tmn _ _ ?tmn = insn_unreachable _ |- _ => 
      destruct tmn; inv H11; auto
    end.

  Case "4".

    right; right; right; left;
    destruct St2 as [[|[? ? [|[] CurCmds] tmn' Locals] ?] ?]; try solve [
      tauto |

      inv_mbind; destruct Hundef as [gn [EQ Hundef]]; inv EQ; inv_mbind;
      undefined_state__State_simulation_r2l_tac41;
      undefined_state__la_State_simulation_r2l_tac43;
        repeat fill_ctxhole; exists gn; fill_ctxhole; auto
    ].

  Case "5".
    right. right. right. right. left.
    destruct St2 as [[|[? ? [|[] CurCmds] tmn' ?] ?] ?]; try tauto.
    inv_mbind; destruct Hundef as [gn [EQ Hundef]]; inv EQ; inv_mbind.
    undefined_state__State_simulation_r2l_tac41.
    undefined_state__la_State_simulation_r2l_tac43.
    repeat fill_ctxhole; exists gn; fill_ctxhole; auto.

  Case "6".
    right. right. right. right. right. left.
    destruct St2 as [[|[? ? [|[] CurCmds] tmn' ?] ?] ?]; try tauto.
    inv_mbind; destruct Hundef as [gvs [EQ Hundef]]; inv EQ; inv_mbind.
    undefined_state__State_simulation_r2l_tac41.
    undefined_state__la_State_simulation_r2l_tac43. 
    repeat fill_ctxhole; exists gvs; fill_ctxhole; auto.

  Case "7".
    right. right. right. right. right. right. left.
    destruct St2 as [[|[? ? [|[] CurCmds] tmn' ?] ?] ?]; try tauto.
    inv_mbind; destruct Hundef as [gv [mgv [EQ1 [EQ2 Hundef]]]]; 
      inv EQ1; inv EQ2; inv_mbind.
    undefined_state__State_simulation_r2l_tac41.
    undefined_state__la_State_simulation_r2l_tac43. 
    repeat fill_ctxhole; exists gv; exists mgv; fill_ctxhole; auto.

  Case "8".
    destruct St2 as [[|[? ? [|[] CurCmds] tmn' ?] ?] ?]; try tauto.
    right; right; right; right. right. right. right.
    undefined_state__State_simulation_r2l_tac41.
    inv_mbind.
    destruct Hundef as [fptr [EQ Hundef]]; inv EQ.
    inv_mbind.
    apply cmds_simulation_cons_inv' in Hstsim; subst;
    destruct Hstsim as [c1' [cs2' [J1 [J2 J3]]]]; subst.
    apply cmd_simulation__cmd_simulation' in J2;
    inv J2.  
    undefined_state__la_State_simulation_r2l_tac42.
    repeat fill_ctxhole.
    exists fptr. split; auto.
    remember (OpsemAux.lookupExFdecViaPtr gl2 FunTable fptr) as R.
    destruct R as [[[]]|].
      inv_mbind.
      destruct Hundef as [gvs0 [EQ Hundef]].
      dgvs_instantiate_inv.
      assert (exists gvs, 
                Opsem.params2GVs (los2,nts2) lp0 Locals fs2 = Some gvs) as G'.
        destruct H4 as [l5 [ps2 [cs21 H4]]]; subst.
        destruct Hwfcfg1 as [_ [Hwfg1 [Hwfs1 HmInS1]]];
        destruct Hwfpp1 as [_ [[Hreach1 [HbInF1 [HfInPs1 [_ [Hinscope1 _]]]]] _]].
        inv_mbind.
        eapply OpsemPP.params2GVs_isnt_stuck; eauto 1; simpl; auto.
          exists nil. auto.
      destruct G' as [gvs' G'].
      assert (gvs' = l1) as EQ.
        destruct H4 as [l5 [ps1 [cs11 H4]]]; subst;
        destruct Hwfcfg1 as [_ [Hwfg1 [Hwfs1 HmInS1]]];
        destruct Hwfpp1 as [_ [[Hreach1 [HbInF1 [HfInPs1 [_ [Hinscope1 _]]]]] _]];
        destruct HwfS1 as [HwfS1 _];
        unfold wf_ExecutionContext, inscope_of_ec in HwfS1;
        inv_mbind.
        eapply params2GVs_sim; 
          eauto 2 using wf_system__wf_fdef, wf_system__uniqFdef; 
            try solve [simpl; auto].
      subst.
      repeat fill_ctxhole.
      erewrite TopSim.lookupFdefViaPtr__simulation_None_l2r; eauto.
      erewrite TopSim.lookupExFdecViaPtr__simulation_r2l; eauto.
      simpl.
      exists l1. split; auto.
    
      erewrite TopSim.lookupFdefViaPtr__simulation_None_l2r; eauto.
      erewrite TopSim.lookupExFdecViaPtr__simulation_None_r2l; eauto.
Qed.

Lemma find_st_ld__lasinfo: forall l0 ps0 cs0 tmn0 i0 v cs (pinfo:PhiInfo) dones
  (Hst : ret inl (i0, v, cs) = find_init_stld cs0 (PI_id pinfo) dones)
  (i1 : id) (Hld : ret inl i1 = find_next_stld cs (PI_id pinfo))
  (HBinF : blockInFdefB (block_intro l0 ps0 cs0 tmn0) (PI_f pinfo) = true),
  exists lasinfo:LASInfo pinfo,
    LAS_lid pinfo lasinfo = i1 /\
    LAS_sid pinfo lasinfo = i0 /\
    LAS_value pinfo lasinfo = v /\
    LAS_block pinfo lasinfo = (block_intro l0 ps0 cs0 tmn0).
Admitted. (* lasinfo *)

Lemma sop_star__las_State_simulation: forall pinfo lasinfo cfg1 IS1 cfg2 IS2 tr
  FS2 (Hwfpi: WF_PhiInfo pinfo)
  (Hwfcfg1: OpsemPP.wf_Config cfg1) (Hwfcfg2: OpsemPP.wf_Config cfg2) 
  (Hwfpp1: OpsemPP.wf_State cfg1 IS1) (Hwfpp2: OpsemPP.wf_State cfg2 IS2) 
  (HwfS1: id_rhs_val.wf_State (value_id (LAS_lid pinfo lasinfo)) 
           (LAS_value pinfo lasinfo) (PI_f pinfo) cfg1 IS1) stinfo Hp
  (Hsubst: substable_values (OpsemAux.CurTargetData cfg1) (OpsemAux.Globals cfg1)
             (PI_f pinfo) (value_id (LAS_lid pinfo lasinfo))
             (LAS_value pinfo lasinfo))
  (Hlas2st : exist _ stinfo Hp = lasinfo__stinfo pinfo lasinfo)
  (Halst: alive_store.wf_State pinfo stinfo cfg1 IS1)
  (Hstsim : State_simulation pinfo lasinfo cfg1 IS1 cfg2 IS2) maxb
  (Hless: 0 <= maxb) (Hwfgs: MemProps.wf_globals maxb (OpsemAux.Globals cfg1))
  (Hnoalias: Promotability.wf_State maxb pinfo cfg1 IS1)
  (Hopstar : Opsem.sop_star cfg2 IS2 FS2 tr) (Hok: ~ sop_goeswrong cfg1 IS1),
  exists FS1, Opsem.sop_star cfg1 IS1 FS1 tr /\
    State_simulation pinfo lasinfo cfg1 FS1 cfg2 FS2.
Proof.
  intros.
  generalize dependent cfg1.
  generalize dependent IS1.
  induction Hopstar; intros.
    exists IS1. split; auto.

    assert (forall (Hfinal1: Opsem.s_isFinialState cfg1 IS1 <> merror),
            exists FS1 : Opsem.State,
              Opsem.sop_star cfg1 IS1 FS1 (tr1 ** tr2) /\
              State_simulation pinfo lasinfo cfg1 FS1 cfg2 state3) as W.
      intros.
      apply s_isFinialState__las_State_simulation in Hstsim; auto.
      rewrite Hstsim in Hfinal1.
      contradict H; eauto using s_isFinialState__stuck.
    assert (J:=Hwfpp1).
    apply OpsemPP.progress in J; auto.
    destruct J as [Hfinal1 | [[IS1' [tr0 Hop1]] | Hundef1]]; auto.
      eapply las_is_sim in Hstsim; eauto.
      destruct Hstsim as [Hstsim EQ]; subst.
      assert (OpsemPP.wf_State cfg1 IS1') as Hwfpp1'.
        apply OpsemPP.preservation in Hop1; auto.
      assert (vev_State (value_id (LAS_lid pinfo lasinfo))
               (LAS_value pinfo lasinfo) (PI_f pinfo) cfg1 IS1) as Hvev.
        eapply las__alive_store__vev; eauto.
      assert (id_rhs_val.wf_State (value_id (LAS_lid pinfo lasinfo))
               (LAS_value pinfo lasinfo) (PI_f pinfo) cfg1 IS1') as HwfS1'.
        eapply id_rhs_val.preservation in Hop1; eauto.
      assert (alive_store.wf_State pinfo stinfo cfg1 IS1') as Halst'.
        eapply alive_store.preservation in Hop1; eauto.
      assert (Promotability.wf_State maxb pinfo cfg1 IS1') as Hnoalias'.
        eapply Promotability.preservation in Hop1; eauto.
      eapply IHHopstar in Hstsim; 
        eauto using sop_goeswrong__step, (@OpsemPP.preservation DGVs).
      destruct Hstsim as [FS1 [Hopstar1 Hstsim]].
      exists FS1.
      split; eauto.

      apply undefined_state__stuck' in Hundef1.
      remember (Opsem.s_isFinialState cfg1 IS1) as R.
      destruct R.
        apply W; congruence.
        contradict Hok. exists IS1. exists E0. split; auto.
Qed.

Lemma sop_div__las_State_simulation: forall pinfo lasinfo cfg1 IS1 cfg2 IS2 tr
  (Hwfpi: WF_PhiInfo pinfo) (Hwfpp: OpsemPP.wf_State cfg1 IS1)
  (HwfS1: id_rhs_val.wf_State (value_id (LAS_lid pinfo lasinfo))
           (LAS_value pinfo lasinfo) (PI_f pinfo) cfg1 IS1) stinfo Hp
  (Hsubst: substable_values (OpsemAux.CurTargetData cfg1) (OpsemAux.Globals cfg1)
             (PI_f pinfo) (value_id (LAS_lid pinfo lasinfo))
             (LAS_value pinfo lasinfo))
  (Hlas2st : exist _ stinfo Hp = lasinfo__stinfo pinfo lasinfo)
  (Halst: alive_store.wf_State pinfo stinfo cfg1 IS1)
  (Hstsim : State_simulation pinfo lasinfo cfg1 IS1 cfg2 IS2) maxb
  (Hless: 0 <= maxb) (Hwfgs: MemProps.wf_globals maxb (OpsemAux.Globals cfg1))
  (Hnoalias: Promotability.wf_State maxb pinfo cfg1 IS1)
  (Hstsim : State_simulation pinfo lasinfo cfg1 IS1 cfg2 IS2)
  (Hopstar : Opsem.sop_diverges cfg2 IS2 tr),
  Opsem.sop_diverges cfg1 IS1 tr.
Admitted. (* sop_div *)

Lemma las_wfS: forall (los : layouts) (nts : namedts) (fh : fheader)
  (dones : list id) (pinfo: PhiInfo)
  (bs1 : list block) (l0 : l) (ps0 : phinodes) (cs0 : cmds) (tmn0 : terminator)
  (bs2 : list block) (Ps1 : list product) (Ps2 : list product) (i0 : id)
  (v : value) (cs : cmds) (Hwfpi: WF_PhiInfo pinfo)
  (Hst : ret inl (i0, v, cs) = find_init_stld cs0 (PI_id pinfo) dones)
  (i1 : id) (Hld : ret inl i1 = find_next_stld cs (PI_id pinfo))
  (HwfS :
     wf_system 
       [module_intro los nts
         (Ps1 ++
          product_fdef
            (fdef_intro fh (bs1 ++ block_intro l0 ps0 cs0 tmn0 :: bs2))
          :: Ps2)])
  (Heq: PI_f pinfo = fdef_intro fh (bs1 ++ block_intro l0 ps0 cs0 tmn0 :: bs2)),
  wf_system 
    [module_intro los nts
      (Ps1 ++
       product_fdef
         (subst_fdef i1 v
           (fdef_intro fh (bs1 ++ block_intro l0 ps0 cs0 tmn0 :: bs2))) :: Ps2)].
Proof.
Admitted.  (* WF prev *)

Lemma vev_State_preservation : forall pinfo lasinfo cfg IS maxb
  (Hwfg: MemProps.wf_globals maxb (OpsemAux.Globals cfg))
  (Halias: Promotability.wf_State maxb pinfo cfg IS) (Hwfpi: WF_PhiInfo pinfo)
  stinfo Hp (Hlas2st : exist _ stinfo Hp = lasinfo__stinfo pinfo lasinfo)
  (Halst: alive_store.wf_State pinfo stinfo cfg IS)
  (Hwfcfg : OpsemPP.wf_Config cfg) (Hwfpp: OpsemPP.wf_State cfg IS) 
  (Hvev: vev_State (value_id (LAS_lid pinfo lasinfo))
               (LAS_value pinfo lasinfo) (PI_f pinfo) cfg IS)
  IS' tr  (Hstep: Opsem.sInsn cfg IS IS' tr),
  vev_State (value_id (LAS_lid pinfo lasinfo))
               (LAS_value pinfo lasinfo) (PI_f pinfo) cfg IS'.
Proof.
  intros.
  eapply las__alive_store__vev; eauto.
    apply OpsemPP.preservation in Hstep; auto.
    eapply alive_store.preservation in Hstep; eauto.
Qed.

Lemma id_rhs_val_preservation_star : forall v1 v2 F pinfo lasinfo cfg IS IS' tr
  (Heq1: v1 = value_id (LAS_lid pinfo lasinfo))
  (Heq2: v2 = LAS_value pinfo lasinfo) (Heq3: F = PI_f pinfo) maxb (Hle: 0 <= maxb)
  (Hwfg: MemProps.wf_globals maxb (OpsemAux.Globals cfg))
  (Halias: Promotability.wf_State maxb pinfo cfg IS) (Hwfpi: WF_PhiInfo pinfo)
  stinfo Hp (Hlas2st : exist _ stinfo Hp = lasinfo__stinfo pinfo lasinfo)
  (Halst: alive_store.wf_State pinfo stinfo cfg IS)
  (Hvals : substable_values (OpsemAux.CurTargetData cfg) (OpsemAux.Globals cfg)
             F v1 v2) (Hvev: vev_State v1 v2 F cfg IS) 
  (Hwfcfg : OpsemPP.wf_Config cfg) (Hwfpp: OpsemPP.wf_State cfg IS) 
  (HwfS1: id_rhs_val.wf_State v1 v2 F cfg IS) (Hstar: Opsem.sop_star cfg IS IS' tr),
  id_rhs_val.wf_State v1 v2 F cfg IS'.
Proof.
  intros. subst.
  induction Hstar; auto.
    apply IHHstar; auto.
      eapply Promotability.preservation; eauto.
      eapply alive_store.preservation; eauto.
      eapply OpsemPP.preservation; eauto.
      eapply vev_State_preservation; eauto.
      eapply id_rhs_val.preservation; eauto.
Qed.  

Lemma las_sim: forall (los : layouts) (nts : namedts) (fh : fheader)
  (dones : list id) (pinfo: PhiInfo) (main : id) (VarArgs : list (GVsT DGVs))
  (bs1 : list block) (l0 : l) (ps0 : phinodes) (cs0 : cmds) (tmn0 : terminator)
  (bs2 : list block) (Ps1 : list product) (Ps2 : list product) (i0 : id)
  (v : value) (cs : cmds) (Hwfpi: WF_PhiInfo pinfo)
  (Hst : ret inl (i0, v, cs) = find_init_stld cs0 (PI_id pinfo) dones)
  (i1 : id) (Hld : ret inl i1 = find_next_stld cs (PI_id pinfo))
  S2 (Heq2: S2=[module_intro los nts
                (Ps1 ++
                  product_fdef
                    (fdef_intro fh (bs1 ++ block_intro l0 ps0 cs0 tmn0 :: bs2))
                  :: Ps2)])
  (Hok: defined_program S2 main VarArgs)
  (HwfS : wf_system S2)
  (Heq: PI_f pinfo = fdef_intro fh (bs1 ++ block_intro l0 ps0 cs0 tmn0 :: bs2)),
  program_sim
    [module_intro los nts
      (Ps1 ++
       product_fdef
         (subst_fdef i1 v
            (fdef_intro fh (bs1 ++ block_intro l0 ps0 cs0 tmn0 :: bs2))) :: Ps2)]
    S2 main VarArgs.
Proof.
  intros. subst.
  assert (blockInFdefB (block_intro l0 ps0 cs0 tmn0) (PI_f pinfo) = true)
    as HBinF.
    rewrite Heq. simpl. apply InBlocksB_middle.
  eapply find_st_ld__lasinfo in HBinF; eauto.
  destruct HBinF as [lasinfo [J1 [J2 [J3 J4]]]]; subst.
  assert (Huniq:=HwfS). apply wf_system__uniqSystem in Huniq; auto.
  assert (system_simulation pinfo lasinfo
     [module_intro los nts
        (Ps1 ++
         product_fdef
           (fdef_intro fh (bs1 ++ block_intro l0 ps0 cs0 tmn0 :: bs2)) :: Ps2)]
     [module_intro los nts
        (Ps1 ++
         product_fdef
           (subst_fdef (LAS_lid pinfo lasinfo) (LAS_value pinfo lasinfo)
              (fdef_intro fh (bs1 ++ block_intro l0 ps0 cs0 tmn0 :: bs2)))
         :: Ps2)]) as Hssim.
    constructor; auto.
    repeat split; auto.
    simpl in Huniq. destruct Huniq as [[_ [_ Huniq]] _].
    unfold TopSim.products_simulation. unfold fsim. unfold Fsim.
    apply uniq_products_simulation; auto.

  assert (wf_fdef [module_intro los nts (Ps1++product_fdef (PI_f pinfo)::Ps2)]
            (module_intro los nts (Ps1++product_fdef (PI_f pinfo)::Ps2)) 
            (PI_f pinfo)) as HwfF.
    admit. (* wfF *)
  assert (uniqFdef (PI_f pinfo)) as HuniqF.
    admit. (* wfF *)

Ltac las_sim_init :=
match goal with
| H: Opsem.s_genInitState [module_intro ?los ?nts _] _ _ _ = Some (?cfg, ?IS),  
  pinfo: PhiInfo, lasinfo: LASInfo _
  |- _ =>
    assert (OpsemPP.wf_Config cfg /\ OpsemPP.wf_State cfg IS) as Hwfst';
      try solve [eapply s_genInitState__opsem_wf in H; eauto using las_wfS];
    eapply s_genInitState__las_State_simulation in H; eauto;
    destruct H as [cfg1 [IS1 [Hinit Hstsim]]];
    assert (OpsemPP.wf_Config cfg1 /\ OpsemPP.wf_State cfg1 IS1) as Hwfst;
      try solve [eapply s_genInitState__opsem_wf; eauto];
    assert (substable_values (OpsemAux.CurTargetData cfg1) (OpsemAux.Globals cfg1)
      (PI_f pinfo) (value_id (LAS_lid pinfo lasinfo)) (LAS_value pinfo lasinfo)) 
      as Hdom; try solve [
      assert ((los,nts) = OpsemAux.CurTargetData cfg1) as EQ;
        try solve [eapply s_genInitState__targedata; eauto];
      rewrite <- EQ;
      eapply LAS_substable_values; eauto
      ];
    assert (id_rhs_val.wf_State (value_id (LAS_lid pinfo lasinfo))
              (LAS_value pinfo lasinfo) (PI_f pinfo) cfg1 IS1) as Hisrhsval;
      try solve [eapply s_genInitState__id_rhs_val; eauto];
    assert (exists maxb,
              MemProps.wf_globals maxb (OpsemAux.Globals cfg1) /\ 0 <= maxb /\
              Promotability.wf_State maxb pinfo cfg1 IS1) as Hprom;
      try solve [eapply Promotability.s_genInitState__wf_globals_promotable; eauto];
    destruct Hprom as [maxb [Hwfg [Hless Hprom]]];
    remember (lasinfo__stinfo pinfo lasinfo) as R;
    destruct R as [stinfo Hp];
    assert (alive_store.wf_State pinfo stinfo cfg1 IS1) as Halst;
      try solve [eapply s_genInitState__alive_store; eauto]
end.

Ltac las_sim_end :=
 match goal with
| Hstsim' : State_simulation ?pinfo ?lasinfo ?cfg1 ?FS1 ?cfg ?FS,
  Hopstar1 : Opsem.sop_star ?cfg1 _ ?FS1 _ |- _ =>
    assert (OpsemPP.wf_State cfg FS) as Hwfst''; 
      try solve [eapply OpsemPP.preservation_star; eauto; try tauto];
    assert (OpsemPP.wf_State cfg1 FS1) as Hwfst1'';
      try solve [eapply OpsemPP.preservation_star; eauto; try tauto];
    assert (wf_State (value_id (LAS_lid pinfo lasinfo)) (LAS_value pinfo lasinfo)
      (PI_f pinfo) cfg1 FS1); try solve [
      eapply id_rhs_val_preservation_star in Hopstar1; eauto; try solve [
        tauto |
        eapply las__alive_store__vev; eauto; try tauto
      ]
    ]
end.

  constructor; auto.
    intros tr t Hconv.
    inv Hconv.
    las_sim_init.
    eapply sop_star__las_State_simulation in Hstsim; 
      eauto using defined_program__doesnt__go_wrong; try tauto.
    destruct Hstsim as [FS1 [Hopstar1 Hstsim']].
    las_sim_end.
    match goal with
    | Hstsim' : State_simulation _ _ _ _ ?cfg ?FS,
      H: Opsem.s_isFinialState ?cfg ?FS = _ |- _ =>
      eapply s_isFinialState__las_State_simulation in Hstsim'; eauto; try tauto;
      rewrite <- Hstsim' in H
    end.
    econstructor; eauto.

    intros tr Hdiv.
    inv Hdiv.
    las_sim_init.
    eapply sop_div__las_State_simulation in Hstsim; eauto; try tauto.
    destruct Hstsim as [FS1 Hopdiv1].
    econstructor; eauto.

    intros tr t Hgowrong.
    inv Hgowrong.
    assert (OpsemPP.wf_Config cfg /\ OpsemPP.wf_State cfg t) as HwfSt.
      eapply s_genInitState__opsem_wf in H; eauto using las_wfS.
      destruct H as [Hcfg2 HwfSt2].
      apply OpsemPP.preservation_star in H0; auto.
    assert (OpsemPP.undefined_state cfg t) as Hundef.
      apply stuck__undefined_state in H2; try solve [auto | tauto].
    las_sim_init.
    eapply sop_star__las_State_simulation in Hstsim;
      eauto using defined_program__doesnt__go_wrong; try tauto.
    destruct Hstsim as [FS1 [Hopstar1 Hstsim']].
    assert (Hprom':=Hprom).
    eapply Promotability.preservation_star in Hprom'; eauto; try tauto.
    las_sim_end.
    assert (OpsemPP.undefined_state cfg1 FS1) as Hundef'.
      eapply undefined_state__las_State_simulation_r2l in Hundef; 
        try solve [eauto | tauto].
    assert (Opsem.s_isFinialState cfg1 FS1 = merror) as Hfinal'.
      erewrite <- s_isFinialState__las_State_simulation in H2; 
        try solve [eauto | tauto].
    apply undefined_state__stuck' in Hundef'.
    exists tr. exists FS1.
    econstructor; eauto.
Qed.

Lemma las_wfPI: forall (los : layouts) (nts : namedts) (fh : fheader)
  (dones : list id) (pinfo: PhiInfo)
  (bs1 : list block) (l0 : l) (ps0 : phinodes) (cs0 : cmds) (tmn0 : terminator)
  (bs2 : list block) (Ps1 : list product) (Ps2 : list product) (i0 : id)
  (v : value) (cs : cmds) (Hwfpi: WF_PhiInfo pinfo)
  (Hst : ret inl (i0, v, cs) = find_init_stld cs0 (PI_id pinfo) dones)
  (i1 : id) (Hld : ret inl i1 = find_next_stld cs (PI_id pinfo))
  (HwfS :
     wf_system 
       [module_intro los nts
         (Ps1 ++
          product_fdef
            (fdef_intro fh (bs1 ++ block_intro l0 ps0 cs0 tmn0 :: bs2))
          :: Ps2)])
  (Heq: PI_f pinfo = fdef_intro fh (bs1 ++ block_intro l0 ps0 cs0 tmn0 :: bs2)),
  WF_PhiInfo
    (update_pinfo pinfo
      (subst_fdef i1 v
        (fdef_intro fh (bs1 ++ block_intro l0 ps0 cs0 tmn0 :: bs2)))).
Proof.
Admitted.  (* WF prev *)

