Require Import ListSet.
Require Import vellvm_tactics.
Require Import Coq.Lists.List.
Require Import CoqListFacts.
Require Import Metatheory.
Require Import Coqlib.

(* In *)

Lemma In_weakening : forall A (l2 l3 l1:list A) a,
  In a (l1 ++ l3) -> In a (l1 ++ l2 ++ l3).
Proof.
  induction l1; simpl; intros.
    apply in_or_app; auto.
    destruct H as [H | H]; auto.
Qed.

Lemma In_middle : forall A (c:A) cs1 cs2, In c (cs1++c::cs2).
Proof.
  induction cs1; simpl; auto.
Qed.

Lemma notin_app_inv: forall A (l1 l2:list A) a,
  ~ In a (l1 ++ l2) -> ~ In a l1 /\ ~ In a l2.
Proof.
  intros.
  split; intro J; apply H; apply in_or_app; auto.
Qed.

Lemma notin_app: forall A (l1 l2:list A) a,
  ~ In a l1 -> ~ In a l2 ->
  ~ In a (l1 ++ l2).
Proof.
  intros. intro J.
  apply in_app_or in J.
  destruct J as [J | J].
    apply H; auto.
    apply H0; auto.
Qed.

Lemma in_middle : forall A (c:A) cs1 cs2, In c (cs1 ++ c :: cs2).
Proof.
  intros.
  apply in_app_iff; simpl; auto.
Qed.

Lemma in_first_chunk: forall X (a:X) A B C, In a A -> In a (A++B++C).
Proof.
  intros. apply in_or_app. auto.
Qed.

Lemma in_second_chunk: forall X (b:X) A B C, In b B -> In b (A++B++C).
Proof.
  intros. apply in_or_app. right. apply in_or_app. auto.
Qed.

Lemma in_third_chunk: forall X (c:X) A B C, In c C -> In c (A++B++C).
Proof.
  intros. apply in_or_app. right. apply in_or_app. auto.
Qed.

Ltac destruct_in H :=
match type of H with
| In _ [_] => simpl in H; destruct H as [H | H]; subst; try tauto
| In _ (_::_) => simpl in H; destruct H as [H | H]; subst; try tauto
| In _ (_++_) => apply in_app_or in H; destruct H as [H | H]
end.

(* map *) 
Lemma map_app_inv : forall A B l1 l2 l (f:A->B),
  List.map f l = l1 ++ l2 ->
  exists l1', exists l2',
    l = l1' ++ l2' /\ List.map f l1' = l1 /\ List.map f l2' = l2.
Proof.
  induction l1; simpl; intros.
    exists nil. exists l. auto.

    destruct l; inv H.
    apply IHl1 in H2. destruct H2 as [l1' [l2' [J1 [J2 J3]]]]; subst.
    exists (a0::l1'). exists l2'. auto.
Qed.

Lemma fst_split__map_fst: forall A B (l1:list (A*B)),
  fst (split l1) = List.map fst l1.
Proof.
  induction l1 as [|[]]; simpl; auto.
    destruct_let. simpl. rewrite <- IHl1. auto.
Qed.

Lemma snd_split__map_snd: forall A B (l1:list (A*B)),
  snd (split l1) = List.map snd l1.
Proof.
  induction l1 as [|[]]; simpl; auto.
    destruct_let. simpl. rewrite <- IHl1. auto.
Qed.

Lemma map_id_ext {A : Type} (f : A -> A) (l : list A) :
  (forall a : A, f a = a) -> List.map f l = l.
Proof.
  intros H. induction l as [|a l]. trivial.
  simpl. rewrite H. rewrite IHl. trivial.
Qed.

Lemma map_cons_inv: forall A (x y2:list A) a' f (Heq: List.map f x = a' :: y2),
  exists a, exists x2, x = a :: x2 /\ List.map f x2 = y2 /\ f a = a'.
Proof.
  intros.
  destruct x as [|a x]; inv Heq.
    eauto.
Qed.

Lemma In_fst__in_dom: forall X (A:list (atom*X)) i0,
  In i0 (List.map fst A) <-> i0 `in` dom A.
Proof.
  induction A as [|[] A]; simpl; intros; auto.
    split; intro J.
      inv J. fsetdec.

    split; intro J.
      destruct J as [J | J]; subst; auto.
        apply IHA in J; auto.

      apply AtomSetFacts.add_iff in J.
      destruct J as [J | J]; subst; auto.
        apply IHA in J; auto.
Qed.

(* list *) 
Lemma in_dom__iff__in_rev_dom: forall i0 X (A:list (atom*X)),
  i0 `in` dom A <-> i0 `in` dom (rev A).
Proof.
  induction A as [|[] A]; simpl.
    split; auto.

    rewrite dom_app. simpl.
    fsetdec.
Qed.

Lemma app_split: forall A (x y z u:list A) a (Heq: x ++ y = z ++ a :: u),
  (exists u1, exists u2, x = z ++ a :: u1 /\ y = u2 /\ u = u1 ++ u2) \/
  (exists z1, exists z2, x = z1 /\ y = z2 ++ a :: u /\ z = z1 ++ z2).
Proof.
  induction x as [|x1 x]; simpl; intros; subst.
    right. exists nil. eauto.

    destruct z as [|z1 z].
      inv Heq. simpl. left. exists x. eauto.

      inv Heq.
      apply_clear IHx in H1.
      destruct H1 as [[u1 [u2 [J1 [J2 J3]]]]|[z1' [z2 [J1 [J2 J3]]]]]; subst.
        left. exists u1. exists u2. eauto.
        right. exists (z1::z1'). eauto.
Qed.

Lemma Forall_app: forall A P (x y:list A) (Hx: Forall P x) (Hy: Forall P y),
  Forall P (x++y).
Proof.
  induction 1; intros; auto.
    constructor; auto.
Qed.

Lemma rev_non_nil: forall A (ls1:list A),
  ls1 <> nil <-> rev ls1 <> nil.
Proof.
  induction ls1; simpl.
    split; auto.  
    split; intro J; auto with datatypes v62.      
Qed.

Lemma cons_last: forall A (hd:A) tl, 
  exists pre, exists last, hd::tl = pre++[last].
Proof.
  intros.
  assert (hd::tl <> nil) as Hnnil.
    congruence.
  apply exists_last in Hnnil.
  destruct Hnnil as [? [? ?]].
  eauto.
Qed.

Lemma app_cons_is_larger: forall A cs3 cs2 (c:A),
  cs2 = cs3 ++ c :: cs2 -> False.
Proof.
  intros.
  assert (J:=app_length cs3 (c::cs2)).
  rewrite <- H in J.
  simpl in J. omega.
Qed.

Lemma app_inv_tail_nil : forall A (l1 l2:list A),
  l1 ++ l2 = l2 -> l1 = nil.
Proof.
  intros.
  change l2 with (nil ++ l2) in H at 2.
  apply app_inv_tail in H; auto.
Qed.

Lemma head_tail_commut: forall A (a:A) cs,
  exists cs', exists a', [a] ++ cs = cs' ++ [a'].
Proof.
  induction cs.
    exists nil. exists a. auto.

    destruct IHcs as [cs' [a' IHcs]].
    destruct cs'.
      inv IHcs.
      exists [a']. exists a0. auto.

      inv IHcs.
      exists ([a1]++a0::cs'). exists a'. auto.
Qed.

Lemma app_middle_split: forall A (l1 l2 l3 l4:list A) a,
  l1++a::l2 = l3++l4 ->
  (exists l12, l1 = l3++l12 /\ l4 = l12++a::l2) \/
  (exists l21, l3 = l1++a::l21 /\ l2 = l21++l4).
Proof.
  induction l1; simpl; intros.
    destruct l3.
      destruct l4; inv H.
        left. exists nil. auto.
      inv H. right. exists l3. auto.

    destruct l3.
      destruct l4; inv H.
        left. exists (a1::l1). auto.
      inv H. apply IHl1 in H2.
      destruct H2 as [[l21 [J1 J2]]|[l21 [J1 J2]]]; subst; simpl; eauto.
Qed.

Lemma split_r_in : forall A B (l1:list (A*B))(b:B),
  In b (snd (split l1)) -> exists a, In (a,b) l1.
Proof.
  induction l1 as [|[]]; simpl; intros; try tauto.
    destruct_let. simpl in *.
    destruct H as [H | H]; subst; eauto.
      apply IHl1 in H. 
      destruct H as [a0 H]. eauto.
Qed.

Lemma split_l_in : forall A B (l1:list (A*B))(a:A),
  In a (fst (split l1)) -> exists b, In (a,b) l1.
Proof.
  induction l1 as [|[]]; simpl; intros; try tauto.
    destruct_let. simpl in *.
    destruct H as [H | H]; subst; eauto.
      apply IHl1 in H. 
      destruct H as [b0 H]. eauto.
Qed.

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
    contradict H; simpl_env; simpl; apply CoqListFacts.app_cons_not_nil
| H: _++[_]++_ = nil |- _ => contradict H; simpl; apply CoqListFacts.app_cons_not_nil
| H: ?A++[?a] = nil |- _ => 
       rewrite_env (A++[a]++nil) in H;
       contradict H; simpl; apply CoqListFacts.app_cons_not_nil
end.

Lemma list_prop1: forall A (l1 l3 l4:list A) a2 a5,
  l1 ++ [a2] ++ l3 = l4 ++ [a5] ->
  exists l6, [a2] ++ l3 = l6 ++ [a5].
Proof.
  induction l1; simpl; intros.
    exists l4. auto.

    destruct l4; inv H.
      anti_simpl_env.
      simpl in *. apply IHl1 in H2; auto.
Qed.

Lemma list_prop2: forall A (l2:list A) (H: (length l2 > 0)%nat),
  exists l1, exists b2, l2 = l1 ++ [b2].
Proof.
  induction l2; simpl; intros.
    contradict H. omega.

    destruct l2.
      exists nil. exists a. auto.

      destruct IHl2 as [l1 [b2 J]]; simpl; try omega.
      rewrite J.
      exists (a::l1). exists b2. simpl_env. auto.
Qed.
    
Lemma list_prop3: forall A (a1:A) l2,
  exists l1, exists b2, a1 :: l2 = l1 ++ [b2].
Proof.
  intros.
  apply list_prop2. simpl. omega.
Qed.

Lemma list_suffix_dec: forall A (Hdec: forall (x y : A), {x = y}+{x <> y})
  (l1 l2: list A), (exists l3, l1 = l3 ++ l2) \/ (~ exists l3, l1 = l3 ++ l2).
Proof.
  induction l2; simpl; eauto.
    destruct IHl2 as [IHl2 | IHl2].
      destruct IHl2 as [l3 IHl2]; subst.
      destruct l3.
        right.
        intro J. destruct J as [l3 J].
        anti_simpl_env.

        destruct (@list_prop3 _ a0 l3) as [l4 [b5 J]].
        rewrite J.
        destruct (@Hdec b5 a); subst.
          left. exists l4. simpl_env. auto.
          right. intro J'. destruct J' as [l6 J'].
          simpl_env in J'. anti_simpl_env. auto.


      right. intro J. apply IHl2.
      destruct J as [l3 J]; subst.
      exists (l3 ++ [a]). simpl_env. auto.
Qed.

(* filter *)
Lemma filter_ext: forall (A:Type) (f g:A->bool)
  (Heq: forall a, f a = g a) (l0:list A), List.filter f l0 = List.filter g l0.
Proof.
  induction l0; intros; simpl; auto.
    rewrite Heq. rewrite IHl0. auto.
Qed.

Lemma filter_true: forall (A:Type) (f:A->bool)
  (Heq: forall a, f a = true) (l0:list A), l0 = List.filter f l0.
Proof.
  induction l0; intros; simpl; auto.
    rewrite Heq. congruence.
Qed.

Lemma filter_app: forall A (check: A -> bool) (l1 l2:list A),
  filter check (l1++l2) = filter check l1 ++ filter check l2.
Proof.
  induction l1; simpl; intros; auto.
    destruct_if.
    rewrite IHl1. simpl_env. auto.
Qed.

(* fold *)
Lemma fold_left_eq : forall B f (J:forall a b, f a b = false -> a = false),
  forall (l1:list B) a, List.fold_left f l1 a = false -> a = false.
Proof.
  induction l1; simpl; intros; eauto.
Qed.

Lemma fold_left_congruence : forall B (f:Prop -> B -> Prop)
  (J:forall (a b:Prop) c, (a->b) -> (f a c -> f b c))
  (l1:list B) (a b:Prop),
  (a -> b) ->
  (List.fold_left f l1 a -> List.fold_left f l1 b).
Proof. induction l1; simpl; intros; eauto. Qed.

Lemma fold_left_prop : forall B (f:Prop -> B -> Prop),
  (forall (a:Prop) b, f a b -> a) ->
  (forall (a b:Prop) c, (a->b) -> (f a c -> f b c)) ->
  forall (l1:list B) (a:Prop),
  (List.fold_left f l1 a -> a).
Proof.
  induction l1; simpl; intros; auto.
    apply IHl1; auto.
    apply fold_left_congruence with (a:=f a0 a); auto.
    apply H.
Qed.

Lemma fold_left_or_false : forall B (f:bool -> B -> bool)
  (J:forall a b, f a b = false -> a = false),
  forall (l1:list B) init,
    List.fold_left f l1 init = false ->
    List.fold_left f l1 false = false /\ init = false.
Proof.
  induction l1; simpl; intros; eauto.
    assert (H':=H).
    apply IHl1 in H.
    destruct H as [H1 H2].
    apply J in H2. subst.
    split; auto.
Qed.

Lemma fold_left_and_true : forall B (f:bool -> B -> bool)
  (J:forall a b, f a b = true -> a = true),
  forall (l1:list B) init,
    List.fold_left f l1 init = true ->
    List.fold_left f l1 true = true /\ init = true.
Proof.
  induction l1; simpl; intros; eauto.
    assert (H':=H).
    apply IHl1 in H.
    destruct H as [H1 H2].
    apply J in H2. subst.
    split; auto.
Qed.

Lemma fold_left_or_spec : forall B (f:bool -> B -> bool)
  (J:forall a b, a = true -> f a b = true),
  forall (l1:list B), List.fold_left f l1 true = true.
Proof.
  induction l1; simpl; intros; eauto.
    rewrite J; auto.
Qed.

Lemma fold_left_or_false_elim : forall B (f: B -> bool)
  l0 init (H:fold_left (fun a b => a || f b) l0 init = false),
  forall x (Hin: In x l0), f x = false.
Proof.
  induction l0; simpl; intros. 
    tauto.

    apply fold_left_or_false in H.
      destruct H as [H1 H2].
      binvf H2 as H3 H4. 
      destruct Hin as [Hin | Hin]; subst; eauto.
      
      intros. binvf H0 as H3 H4. auto.
Qed.

Lemma fold_left_or_true_elim: forall B (f: B -> bool)
  l0 (H:fold_left (fun a b => a || f b) l0 false = true),
  exists x, In x l0 /\ f x = true.
Proof.
  induction l0; simpl; intros. 
    congruence.

    remember (f a) as R. 
    destruct R.
      eauto.
      apply IHl0 in H. destruct H as [x [J1 J2]]. eauto.
Qed.

(* incl *) 
Lemma incl_insert: forall A (l1 l2:list A) a, incl (l1++l2) (l1++a::l2).
Proof.
  induction l1; simpl; intros; intros x J; simpl; auto.
    simpl in J. destruct J as [J | J]; auto.
    right. apply IHl1; auto.
Qed.

Lemma incl_app: forall A (l0 l1 l2:list A),
  incl l1 l2 -> incl (l0++l1) (l0++l2).
Proof.
  intros. intros x J.
  apply in_or_app. apply in_app_or in J.
  destruct J as [J | J]; auto.
Qed.

Lemma incl_nil : forall A (d:list A), incl nil d.
Proof. intros. intros x J. inv J. Qed.

Lemma incl_cons : forall A l1 (x:A), incl l1 (x::l1).
Proof.
  intros. intros y J. simpl; auto.
Qed.

(* index *)
Lemma firstn_nil : forall A n, firstn n (@nil A) = nil.
Proof. induction n; simpl; auto. Qed.

Lemma skipn_nil : forall A n, skipn n (@nil A) = nil.
Proof. induction n; simpl; auto. Qed.

(* NoDup *)

Lemma NotIn_inv : forall X (a:X) (lb1 lb2:list X),
  ~ In a (lb1++lb2) ->
  ~ In a lb1 /\ ~ In a lb2.
Proof.
  intros.
  split; intro J'; apply H; auto using in_or_app.
Qed.

Lemma NoDup_split : forall A (l1 l2:list A),
  NoDup (l1++l2) ->
  NoDup l1 /\ NoDup l2.
Proof.
  induction l1; intros.
    simpl in *.
    split; auto using NoDup_nil.

    inversion H; subst.
    apply IHl1 in H3.
    destruct H3 as [J1 J2].
    split; auto.
      apply NoDup_cons; auto.
        intro J. apply H2. apply in_or_app; auto.
Qed.

Lemma NoDup_last_inv : forall X (a:X) l0,
  NoDup (l0++a::nil) ->
  ~ In a l0.
Proof.
  induction l0; intros.
    intro J. inversion J.

    simpl in H.
    inversion H; subst.
    apply IHl0 in H3.
    intro J.
    simpl in J.
    inversion J; subst; auto.
      apply NotIn_inv in H2.
      destruct H2.
      apply H1; simpl; auto.
Qed.

Lemma NoDup_disjoint : forall X (l2 l1 : list X) (i0 : X),
  NoDup (l1 ++ l2) -> In i0 l2 -> ~ In i0 l1.
Proof.
  induction l1; simpl; intros; auto.
    inversion H; subst.
    intro J.
    destruct J as [J | J]; subst.
      apply H3. apply in_or_app. auto.
      eapply IHl1 in H4; eauto.
Qed.

Ltac solve_NoDup_disjoint :=
match goal with
| H: NoDup (?A++?B++?a::nil) |- ~ In ?a (?A++?B) =>
  rewrite_env ((A++B)++[a]) in H;
  apply NoDup_disjoint with (i0:=a); simpl; eauto
end.

Lemma NoDup_disjoint' : forall l1 l2 (i0:atom),
  NoDup (l1++l2) ->
  In i0 l1 ->
  ~ In i0 l2.
Proof.
  induction l1; intros.
    inversion H0.

    simpl. simpl_env in H.
    inv H. simpl in H0.
    destruct H0 as [H0 | H0]; subst; eauto.
      intro J. apply H3. apply in_or_app; auto.
Qed.

Hint Constructors NoDup.

Ltac split_NoDup :=
repeat match goal with
| Huniq: NoDup (_++_) |- _ =>
  let H1:=fresh "Huniq" in
  let H2:=fresh "Huniq" in
  apply NoDup_split in Huniq;
  destruct Huniq as [H1 H2]
end.

Lemma NoDup_strenthening : forall A (l2 l3 l1:list A),
  NoDup (l1 ++ l2 ++ l3) -> NoDup (l1 ++ l3).
Proof.
  induction l1; simpl; intros.
    apply NoDup_split in H. destruct H; auto.

    inv H. apply NoDup_cons; auto using In_weakening.
Qed.

Lemma NoDup_split': forall A (l1 l2:list A),
  NoDup (l1++l2) ->
  NoDup l1 /\ NoDup l2 /\ (forall (a:A), In a l1 -> ~ In a l2).
Proof.
  induction l1; simpl; intros; auto.
    inv H.
    apply IHl1 in H3. destruct H3 as [J1 [J2 J3]].
    split.
      constructor; auto.
        intro J. apply H2. apply in_or_app; auto.
    split; auto.
      intros.
      destruct H as [H | H]; subst; auto.
        intro J. apply H2. apply in_or_app; auto.
Qed.

Lemma NoDup_insert: forall A (l1 l2:list A) a,
  NoDup (l1++l2) ->
  ~ In a (l1 ++ l2) ->
  NoDup (l1++a::l2).
Proof.
  induction l1; simpl; intros.
    constructor; auto.

    inv H.
    apply IHl1 with (a:=a0) in H4; auto.
    constructor; auto.
      intro J. apply H3.
      apply in_app_or in J.
      apply in_or_app.
      destruct J as [J | J]; auto.
      simpl in J.
      destruct J as [J | J]; auto.
      subst. contradict H0; auto.
Qed.

Lemma NoDup_commut: forall A (l1 l2:list A),
  NoDup (l1++l2) -> NoDup (l2++l1).
Proof.
  induction l1; simpl; intros.
    simpl_env. auto.

    inv H.
    apply NoDup_insert; auto.
    intro J. apply in_app_or in J.
    apply H2. apply in_or_app.
    destruct J as [J | J]; auto.
Qed.

Lemma NoDup_rev: forall A (l1:list A) (Huniq: NoDup l1), NoDup (rev l1).
Proof.
  induction 1; simpl; auto.
    apply NoDup_commut. simpl.
    constructor; auto.
      intro J. apply H. apply in_rev; auto.
Qed.

Lemma NoDup_app: forall A (l1 l2:list A),
  NoDup l1 -> NoDup l2 ->
  (forall (a:A), In a l1 -> ~ In a l2) ->
  NoDup (l1++l2).
Proof.
  induction l1; simpl; intros; auto.
    inv H.
    constructor; auto.
      intro J. apply in_app_or in J.
      destruct J as [J | J]; auto.
      assert (a = a \/ In a l1) as Hin. auto.
      apply H1 in Hin. auto.
Qed.

Lemma NoDup_fst__uniq: forall X (A:list (atom*X)) (Huniq: NoDup (List.map fst A)), 
  uniq A.
Proof.
  induction A as [|[] A]; simpl; intros; auto.
    inv Huniq.
    apply uniq_cons; auto.
      intro J. apply H1. apply In_fst__in_dom; auto.
Qed.

(* uniq *) 
Lemma uniq__iff__uniq_rev: forall X (A:list (atom*X)),
  uniq A <-> uniq (rev A).
Proof.
  induction A as [|[] A]; simpl.
    split; auto.

    split; intro J.
      inv J. 
      apply uniq_app_iff.
      split. apply IHA; auto.
      split. apply uniq_cons; auto.
        apply disjoint_one_r. 
        intro J. apply H3.
        eapply in_dom__iff__in_rev_dom; eauto.

      apply uniq_app_iff in J.
      destruct J as [J1 [J2 J3]].
      apply uniq_cons; auto.
        apply IHA; auto.

        apply disjoint_one_r in J3. 
        intro J. apply J3.
        apply in_dom__iff__in_rev_dom in J; auto.
Qed.

(* nth_err *)

Lemma nil_nth_error_Some__False : forall X n (v:X),
  nth_error (@nil X) n = Some v -> False.
Proof.
  induction n; intros; simpl in *; inversion H.
Qed.

Lemma nth_error_cons__inv : forall X b lb n (b':X),
  nth_error (b::lb) n = Some b' ->
  b = b' \/ (exists n', S n' = n /\ nth_error lb n' = Some b').
Proof.
  destruct n; intros; simpl in *.
    inversion H; auto.

    right. exists n. split; auto.
Qed.

Lemma nth_error_cons__inv' : forall X b lb n (b':X),
  nth_error (b::lb) n = Some b' ->
  (n = O /\ b = b') \/ (exists n', S n' = n /\ nth_error lb n' = Some b').
Proof.
  destruct n; intros; simpl in *.
    inversion H; auto.

    right. exists n. split; auto.
Qed.

Lemma nth_error_In : forall A n (l1:list A) a,
  nth_error l1 n = Some a -> In a l1.
Proof.
  induction n; simpl; intros; destruct l1; inv H; simpl; auto.
Qed.

Lemma nth_error_in {A : Type} (l : list A) (a : A) :
  In a l <-> exists n, nth_error l n = Some a.
Proof.
  split; intros H; induction l as [|a' l]; simpl in *.

    tauto. destruct H as [H | H]. subst. exists O. trivial.
    destruct IHl as [n Hn]; trivial. exists (S n). trivial.

    destruct H as [[|n] Hn]; simpl in *; discriminate.
    destruct H as [[|n] Hn]; simpl in *; eauto.
    inversion Hn. subst. auto.
Qed.

(* length *)
Lemma length_le__length_lt: forall A 
  (eq_dec : forall x y : A, {x = y}+{x <> y})
  (a:A) (l2:list A) (l1:list A) 
  (Huniq: list_norepet l1) (Hinc: incl l1 l2)  
  (Hnotin: ~ In a l1) (Hin: In a l2), 
  (length l1 < length l2)%nat.
Proof.
  intros.
  assert (incl l1 (List.remove eq_dec a l2)) as Hinc'.
    apply remove_notin_incl; eauto with datatypes v62.
  apply incl__length_le in Hinc'; auto.
  assert (length (List.remove eq_dec a l2) < length l2)%nat as Hle.
    apply remove_in_length; auto with datatypes v62.
  omega.
Qed.

(* atom set *)
Section MoreAtomSet.

Variable A:Type.
Variable Hdec: forall x y : atom*A, {x = y} + {x <> y}.

Lemma set_remove_spec3 : forall n n' s (Huniq: uniq s),
  In n' (set_remove Hdec n s) -> n' <> n.
Proof.
  induction 1; intros; simpl in *; auto.
    destruct (Hdec n (x, a)) as [J1 | J2]; subst; simpl in *; auto.
      intro EQ. subst.
      apply binds_dom_contradiction in H0; auto.

      destruct H0 as [H0 | H0]; subst; eauto.
Qed.

Lemma set_remove_notin_doms : forall x n E (Hnotin: x `notin` dom E),
  x `notin` dom (set_remove Hdec n E).
Proof.
  induction E as [|[] E]; simpl; intros; auto.
    destruct_if. 
Qed.

Lemma set_remove_uniq: forall n s (Huniq: uniq s), 
  uniq (set_remove Hdec n s).
Proof.
  induction 1; simpl.
    constructor. 
  
    destruct_if. simpl_env.
    constructor; auto. 
      apply set_remove_notin_doms; auto.
Qed.

Lemma set_remove__seq_eq: forall actions2 actions1 (Huniq1 : uniq actions1)
  (x : AtomSetImpl.elt) (a : A) (H2 : x `notin` dom actions2)
  (Heq : AtomSet.set_eq actions1 ((x, a) :: actions2)),
  AtomSet.set_eq (set_remove Hdec (x, a) actions1) actions2.
Proof.
  intros.
  destruct Heq as [Hincl1 Hincl2].
  split.
    intros y Hiny.
    assert (y <> (x,a)) as Hneq.
      eapply set_remove_spec3 in Hiny; eauto.
    apply AtomSet.set_remove_spec2 in Hiny.
    apply Hincl1 in Hiny.
    destruct_in Hiny; try congruence.

    intros y Hiny.
    apply AtomSet.set_remove_spec1.
      apply Hincl2. simpl. auto.
      intro EQ. subst.
      apply binds_dom_contradiction in Hiny; auto.
Qed.

End MoreAtomSet.
