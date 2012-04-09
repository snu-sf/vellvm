Require Import vellvm.

Ltac wfCall_inv :=
match goal with
| Heq3 : exists _,
           exists _,
             exists _,
               ?B = block_intro _ _ _ _,
  HBinF1 : blockInFdefB ?B ?F = true,
  HwfCall : OpsemPP.wf_call
              {|
              Opsem.CurFunction := ?F;
              Opsem.CurBB := ?B;
              Opsem.CurCmds := nil;
              Opsem.Terminator := _;
              Opsem.Locals := _;
              Opsem.Allocas := _ |}
              ({|
               Opsem.CurFunction := _;
               Opsem.CurBB := _;
               Opsem.CurCmds := ?c' :: _;
               Opsem.Terminator := _;
               Opsem.Locals := _;
               Opsem.Allocas := _ |}  :: _) |- _ =>
  let cs3 := fresh "cs3" in
  destruct Heq3 as [l3 [ps3 [cs3 Heq3]]]; subst;
  assert (HBinF1':=HBinF1);
  apply HwfCall in HBinF1';
  destruct_cmd c'; tinv HBinF1'; clear HBinF1'
end.

Ltac simpl_s_genInitState :=
  match goal with
  | Hinit: Opsem.s_genInitState _ _ _ _ = _ |- _ =>
    unfold Opsem.s_genInitState in Hinit;
    inv_mbind'
  end;
  match goal with
  | m : module |- _ =>
    destruct m as [CurLayouts CurNamedts CurProducts];
    inv_mbind'
  end;
  match goal with
  | H: ret ?b = getEntryBlock ?f |- _ =>
    destruct b as [l0 ps0 cs0 tmn0];
    destruct f as [[f t i0 a v] b];
    inv_mbind'
  end;
  try repeat match goal with
  | H: ret _ = ret _ |- _ => inv H
  end;
  symmetry_ctx.

Ltac uniq_result :=
repeat dgvs_instantiate_inv;
repeat match goal with
| H1 : ?f ?a ?b ?c ?d = _,
  H2 : ?f ?a ?b ?c ?d = _ |- _ =>
  rewrite H1 in H2; inv H2
| H1 : ?f ?a ?b ?c = _,
  H2 : ?f ?a ?b ?c = _ |- _ =>
  rewrite H1 in H2; inv H2
| H1 : ?f ?a ?b = _,
  H2 : ?f ?a ?b = _ |- _ =>
  rewrite H1 in H2; inv H2
| H1 : ?f ?a = _,
  H2 : ?f ?a = _ |- _ =>
  rewrite H1 in H2; inv H2
| H1 : _ @ _ |- _ => inv H1
| H : ?f _ = ?f _ |- _ => inv H
| H : False |- _ => inv H
| H: moduleEqB _ _ = true |- _ => apply moduleEqB_inv in H; inv H
end.

Ltac unfold_blk2GV := unfold blk2GV, ptr2GV, val2GV.

Ltac anti_simpl_env :=
simpl_env in *;
repeat match goal with
| H: ?A ++ _ = ?A ++ _ |- _ => apply app_inv_head in H
| H: ?A ++ ?B ++ ?C = _ |- _ => rewrite_env ((A++B)++C) in H
| H: ?A ++ ?B ++ ?C ++ ?D = _ |- _ => rewrite_env (((A++B)++C)++D) in H
| H: ?A ++ ?B ++ ?C ++ ?D ++ ?E = _ |- _ =>rewrite_env ((((A++B)++C)++D)++E) in H
| H: _ = ?A ++ ?B ++ ?C |- _ => rewrite_env ((A++B)++C) in H
| H: _ = ?A ++ ?B ++ ?C ++ ?D |- _ => rewrite_env (((A++B)++C)++D) in H
| H: _ = ?A ++ ?B ++ ?C ++ ?D ++ ?E |- _ =>rewrite_env ((((A++B)++C)++D)++E) in H
end;
repeat match goal with
| H: _ ++ ?A = _ ++ ?A |- _ => apply app_inv_tail in H
| H: _ ++ [?a] = _ ++ [?b] |- _ => apply app_inj_tail in H; destruct H; subst
| H: ?A = _ ++ ?A |- _ => symmetry in H; apply app_inv_tail_nil in H
| H: _ ++ ?A = ?A |- _ => apply app_inv_tail_nil in H
| H: (_++[_])++_ = nil |- _ => 
    contradict H; simpl_env; simpl; apply app_cons_not_nil
| H: _++[_]++_ = nil |- _ => contradict H; simpl; apply app_cons_not_nil
| H: ?A++[?a] = nil |- _ => 
       rewrite_env (A++[a]++nil) in H;
       contradict H; simpl; apply app_cons_not_nil
end.

(* go to *)
Ltac destruct_dec :=
match goal with
| |- context [id_dec ?b ?a] =>
  destruct (id_dec b a); subst; try congruence; auto
| _ : context [productInModuleB_dec ?p1 ?p2] |- _ =>
  destruct (productInModuleB_dec p1 p2); try congruence
end.

(* go to *)
Lemma getTypeSizeInBits_and_Alignment__getTypeStoreSize: forall TD t sz al,
  getTypeSizeInBits_and_Alignment TD true t = Some (sz, al) ->
  getTypeStoreSize TD t = Some (nat_of_Z (ZRdiv (Z_of_nat sz) 8)).
Proof.
  unfold getTypeStoreSize, getTypeSizeInBits.
  intros. fill_ctxhole. auto.
Qed.


