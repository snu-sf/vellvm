Require Import vellvm.
Require Import Kildall.
Require Import ListSet.
Require Import Maps.
Require Import Lattice.
Require Import Iteration.
Require Import primitives.
Require Import dtree.
Require Import iter_pass.

(*********************************************************************)
(* This file includes two kinds of mem2reg algorithm.
   1) when does_macro_m2r tt = true
      A pipelined algorithm based on a group of primitives, which is
      fully verified.
   2) when does_macro_m2r tt = false
      A algorithm based on dom-tree traversal, and not verified
*)

(*********************************************************************)
(*  The following functions check if an alloca is legal to promote *)
Definition is_promotable_cmd pid :=
  (fun acc0 c =>
          if used_in_cmd pid c then
            match c with
            | insn_load _ _ _ _ => acc0
            | insn_store _ _ v _ _ => negb (valueEqB v (value_id pid)) && acc0
            | _ => false
            end
          else acc0).

Definition is_promotable_fun pid :=
  (fun acc b =>
     let '(block_intro _ ps cs tmn) := b in
     if (List.fold_left (fun re p => re || used_in_phi pid p) ps
          (used_in_tmn pid tmn)) then false
     else
       fold_left (is_promotable_cmd pid) cs acc
  ).

Definition is_promotable (f:fdef) (pid:id) : bool :=
let '(fdef_intro _ bs) := f in
fold_left (is_promotable_fun pid) bs true.

Fixpoint find_promotable_alloca (f:fdef) (cs:cmds) (dones:list id)
  : option (id * typ * value * align) :=
match cs with
| nil => None
| insn_alloca pid ty num al :: cs' =>
    if is_promotable f pid && negb (In_dec id_dec pid dones)
    then Some (pid, ty, num, al)
    else find_promotable_alloca f cs' dones
| _ :: cs' => find_promotable_alloca f cs' dones
end.

(*********************************************************************)
(*  The following is the dom-tree-traversal algorithm, 
    when does_macro_m2r tt = false *)

Record vmap := mkVMap {
  alloca: value;
  others: AssocList value
}.

Definition vm_subst_cmd (vm:vmap) (c:cmd) :=
List.fold_right
  (fun elt c' => let '(id0, v0) := elt in subst_cmd id0 v0 c')
  c vm.(others).

Definition vm_subst_tmn (vm:vmap) (tmn:terminator) :=
List.fold_right
  (fun elt tmn' => let '(id0, v0) := elt in subst_tmn id0 v0 tmn')
  tmn vm.(others).

Definition vm_subst_phi (vm:vmap) (pn:phinode) :=
List.fold_right
  (fun elt pn' => let '(id0, v0) := elt in subst_phi id0 v0 pn')
  pn vm.(others).

Definition vm_get_alloca (vm:vmap): value := vm.(alloca).

Definition vm_set_others (vm:vmap) id0 v0: vmap :=
mkVMap vm.(alloca) (ATree.set id0 v0 vm.(others)).

Definition vm_set_alloca (vm:vmap) v0: vmap :=
mkVMap v0 vm.(others).

Definition ssa_renaming_cmd (c:cmd) (pid:id) (vm: vmap): option cmd * vmap :=
let c' := vm_subst_cmd vm c in
match c' with
| insn_load id0 _ (value_id qid) _ =>
    if (id_dec pid qid) then (None, vm_set_others vm id0 (vm_get_alloca vm))
    else (Some c', vm)
| insn_store _ _ v0 (value_id qid) _ =>
    if (id_dec pid qid) then (None, vm_set_alloca vm v0)
    else (Some c', vm)
| _ => (Some c', vm)
end.

Fixpoint ssa_renaming_cmds (cs:cmds) (pid:id) (vm: vmap) : cmds * vmap :=
match cs with
| nil => (nil, vm)
| c :: cs' =>
    let '(optc0, vm0) := ssa_renaming_cmd c pid vm in
    let '(cs1, vm1) := ssa_renaming_cmds cs' pid vm0 in
    (match optc0 with
     | Some c0 => c0::cs1
     | None => cs1
     end, vm1)
end.

Definition vm_subst_value (vm:vmap) (v:value) :=
List.fold_right
  (fun elt v' => let '(id0, v0) := elt in subst_value id0 v0 v')
  v vm.(others).

Fixpoint ssa_renaming_phis_operands (l0:l) (ps:phinodes) (pid:id)
  (newpids:list id) (vm: vmap) : phinodes :=
match ps with
| nil => nil
| insn_phi id0 t0 vls :: ps' =>
    (if (id_dec id0 pid) || (in_dec id_dec id0 newpids) then
      insn_phi id0 t0
      (List.map
        (fun p : value * l =>
          let '(v1, l1) := p in
               (if (l_dec l0 l1)
                then vm_get_alloca vm
                else v1, l1)) vls)
    else insn_phi id0 t0
          (List.map
            (fun p : value * l =>
              let '(v1, l1) := p in
               (if (l_dec l0 l1)
                then vm_subst_value vm v1
                else v1, l1)) vls))::
    ssa_renaming_phis_operands l0 ps' pid newpids vm
end.

Definition block_subst (f:fdef) (l0:l) (b0:block) : fdef :=
let '(fdef_intro fh bs) := f in
fdef_intro fh
  (List.map (fun b =>
             let '(block_intro l1 _ _ _) := b in
             if (l_dec l1 l0) then b0 else b) bs).

Definition ssa_renaming_succ_phis (f:fdef) (lcur:l) (succ:list l) (pid:id)
  (newpids:list id) (vm:vmap): fdef :=
List.fold_left
  (fun acc lnext =>
   match lookupBlockViaLabelFromFdef acc lnext with
   | None => acc
   | Some (block_intro _ ps cs tmn) =>
       let ps':= ssa_renaming_phis_operands lcur ps pid newpids vm in
       block_subst acc lnext (block_intro lnext ps' cs tmn)
   end) succ f.

Fixpoint update_vm_by_phis (ps:phinodes) (pid:id) (newpids:list id)
  (vm: vmap) : vmap :=
match ps with
| nil => vm
| insn_phi id0 t0 vls :: ps' =>
    if (in_dec id_dec id0 newpids) then vm_set_alloca vm (value_id id0)
    else update_vm_by_phis ps' pid newpids vm
end.

Fixpoint ssa_renaming_dtree (f:fdef) (dt: DTree) (pid:id) (newpids:list id)
  (vm:vmap) : fdef :=
match dt with
| DT_node l0 dts =>
    match lookupBlockViaLabelFromFdef f l0 with
    | None => f
    | Some (block_intro l0 ps cs tmn) =>
        let ps' := List.map (vm_subst_phi vm) ps in
        let vm1 := update_vm_by_phis ps pid newpids vm in
        let '(cs', vm2) := ssa_renaming_cmds cs pid vm1 in
        let tmn' := vm_subst_tmn vm2 tmn in
        let f2 := block_subst f l0 (block_intro l0 ps' cs' tmn') in
        let f3 :=
          ssa_renaming_succ_phis f2 l0
            (successors_terminator tmn) pid newpids vm2 in
        ssa_renaming_dtrees f3 dts pid newpids vm2
    end
end
with ssa_renaming_dtrees (f:fdef) (dts: DTrees) (pid:id)(newpids:list id)
  (vm:vmap) : fdef :=
match dts with
| DT_nil => f
| DT_cons dt dts' =>
    let f' := ssa_renaming_dtree f dt pid newpids vm in
    ssa_renaming_dtrees f' dts' pid newpids vm
end.

Definition vm_init (ty:typ) :=
  mkVMap (value_const (const_undef ty)) (ATree.empty value).

Definition ssa_renaming (f:fdef) (dt:DTree) (pid:id) (ty:typ)
  (newpids:list id) : fdef:=
let f1 := ssa_renaming_dtree f dt pid newpids (vm_init ty) in
if used_in_fdef pid f1 then f1 else remove_fdef pid f1.

Definition insert_phis (f:fdef) (rd:list l) (pid:id) (ty:typ): fdef * list id :=
let preds := XATree.make_predecessors (successors f) in
let '(fdef_intro fh bs) := f in
let ex_ids := getFdefLocs f in
let '(bs', _, newpids) :=
  (List.fold_left
    (fun acc b =>
       let '(bs', ex_ids', newpids) := acc in
       let '(block_intro l0 ps cs tmn) := b in
       match ATree.get l0 preds with
       | Some ((_ :: _) as pds) =>
           let '(exist pid' _) := AtomImpl.atom_fresh_for_list ex_ids' in
           (block_intro l0
             (insn_phi pid' ty
               (fold_left
                  (fun acc p =>
                    ((if In_dec l_dec p rd then value_id pid
                      else value_const (const_undef ty)), p) :: acc)
                   pds nil)::ps)
             cs tmn::bs', pid'::ex_ids', pid'::newpids)
       | _ => (b::bs', ex_ids', newpids)
       end) (List.rev bs) (nil, ex_ids, nil)) in
(fdef_intro fh bs', newpids).

Definition mem2reg_fdef_iter (f:fdef) (dt:DTree) (rd:list l) (dones:list id)
  : fdef * bool * list id :=
match getEntryBlock f with
| Some (block_intro _ _ cs _) =>
    match find_promotable_alloca f cs dones with
    | None => (f, false, dones)
    | Some (pid, ty, num, al) =>
        let '(f', newpids) := insert_phis f rd pid ty in
        (ssa_renaming f' dt pid ty newpids, true, pid::dones)
    end
| _ => (f, false, dones)
end.

Definition mem2reg_fdef_step (dt:DTree) (rd:list l) (st:fdef * list id)
  : (fdef * list id) + (fdef * list id) :=
let '(f, dones) := st in
let '(f1, changed1, dones1) := mem2reg_fdef_iter f dt rd dones in
if changed1 then inr _ (f1, dones1) else inl _ (f1, dones1).

(*********************************************************************)
(*  The following is the pipelined algorithm, when does_macro_m2r tt = true *)

(* generate fresh names for all reachable blocks [rd].
   rd: reachable blocks
   ex_ids: existent variables
   return 1) a map from block name to the fresh load/store/phinode names in the 
             block
          2) new existent variables
*)
Definition gen_fresh_ids (rd:list id) (ex_ids:list atom)
  : (ATree.t (id * id * id) * list atom) :=
  List.fold_left
    (fun acc l0 =>
       let '(nids', ex_ids') := acc in
       let '(exist lid' _) := AtomImpl.atom_fresh_for_list ex_ids' in
       let '(exist pid' _) := AtomImpl.atom_fresh_for_list (lid'::ex_ids') in
       let '(exist sid' _) :=
         AtomImpl.atom_fresh_for_list (pid'::lid'::ex_ids') in
       (ATree.set l0 (lid', pid', sid') nids', sid'::pid'::lid'::ex_ids')
    ) rd (ATree.empty (id * id * id), ex_ids).

(* create a phinode, named [pid'], with incoming labels [pds], of type [ty]
   [nids] holds the fresh ids generated by gen_fresh_ids
*)
Definition gen_phinode (pid':id) (ty:typ) (nids:ATree.t (id*id*id)) (pds:list l)
  : phinode :=
  insn_phi pid' ty
    (fold_left
       (fun acc p =>
            ((match ATree.get p nids with
             | Some (lid0, _, _) => value_id lid0
             | None => value_const (const_undef ty)
             end), p) :: acc)
        pds nil).

(* insert phinode for a promotable id [pid] with type [ty] and alignment [al]) 
   in block b
   [nids] holds the fresh ids generated by gen_fresh_ids
   [succs] maps block to its successors
   [preds] maps block to its predecessors
*)
Definition phinodes_placement_block (pid:id) (ty:typ) (al:align)
  (nids:ATree.t (id*id*id)) (succs preds:ATree.t (list l)) (b:block) : block :=
   let '(block_intro l0 ps cs tmn) := b in
   match ATree.get l0 nids with
   | Some (lid, pid', sid) =>
     let cs' :=
       match ATree.get l0 succs with
       | Some (_::_) => [insn_load lid ty (value_id pid) al]
       | _ => nil
       end in
     match ATree.get l0 preds with
     | Some ((_ :: _) as pds) =>
         block_intro l0
           ((gen_phinode pid' ty nids pds)::ps)
           (insn_store sid ty (value_id pid') (value_id pid) al::
            cs ++ cs') tmn
     | _ => block_intro l0 ps (cs ++ cs') tmn
     end
  | _ => b
  end.

(* insert phindoes for a list of block [bs] *)
Definition phinodes_placement_blocks (pid:id) (ty:typ) (al:align)
  (nids:ATree.t (id*id*id)) (succs preds:ATree.t (list l)) (bs:blocks): blocks:=
List.map (phinodes_placement_block pid ty al nids succs preds) bs.

(* insert phindoes for a function [f] *)
Definition phinodes_placement (rd:list l) (pid:id) (ty:typ) (al:align)
  (succs preds:ATree.t (list l)) (f:fdef) : fdef :=
let '(fdef_intro fh bs) := f in
let '(nids, _) := gen_fresh_ids rd (getFdefLocs f) in
let bs1 := phinodes_placement_blocks pid ty al nids succs preds bs in
fdef_intro fh bs1.

(* find the first element of las/laa/sas pairs in a list of cmds [cs] 
   w.r.t a promotable [pid].
   [dones] records commands we have already seen, preventing revisiting

   The function returns a sum,
     inl (id0, v0, tl) means we found a store with [id0] that stores [v0]
       and followed by a list of [tl]
     inr (v0, tl) means we found an alloca with followed by a list of [tl]
       v0 is always undef
*)
Fixpoint find_init_stld (cs:cmds) (pid:id) (dones:list id)
  : option (id * value * cmds + value * cmds) :=
match cs with
| nil => None
| insn_store sid _ v0 (value_id qid) _ :: cs' =>
    if (in_dec id_dec sid dones) then find_init_stld cs' pid dones
    else
      if (id_dec pid qid) then Some (inl (sid, v0, cs'))
      else find_init_stld cs' pid dones
| insn_alloca qid ty _ _ :: cs' =>
    if (in_dec id_dec qid dones) then find_init_stld cs' pid dones
    else
      if (id_dec pid qid) then
        Some (inr (value_const (const_undef ty), cs'))
      else find_init_stld cs' pid dones
| _ :: cs' => find_init_stld cs' pid dones
end.

(* find the second element of las/laa/sas pairs in a list of cmds [cs] 
   w.r.t a promotable [pid]. 

   The function returns a sum,
     inl (id0) means we found a load [id0]
     inr (id0, v0) means we found a store [id0] with value [v0]
*)
Fixpoint find_next_stld (cs:cmds) (pid:id) : option (id + id * value) :=
match cs with
| nil => None
| insn_store sid _ v0 (value_id qid) _ :: cs' =>
    if (id_dec pid qid) then Some (inr (sid, v0))
    else find_next_stld cs' pid
| insn_load lid _ (value_id qid) _ :: cs' =>
    if (id_dec pid qid) then Some (inl lid)
    else find_next_stld cs' pid
| _ :: cs' => find_next_stld cs' pid
end.

(* given a function [f], in its commands list [cs], we do las/laa/sas
   w.r.t the pairs found by find_init_stld and find_next_stld
*)
Definition elim_stld_cmds (f:fdef) (cs:cmds) (pid:id) (dones:list id)
  : fdef * bool * list id :=
match find_init_stld cs pid dones with
| None => (f, false, dones)
| Some (inl (sid1, v1, cs')) =>
    match find_next_stld cs' pid with
    | None => (f, true, sid1::dones)
    | Some (inl lid) => (remove_fdef lid (subst_fdef lid v1 f), true, dones)
    | Some (inr (sid2, v2)) => (remove_fdef sid1 f, true, dones)
    end
| Some (inr (v1, cs')) =>
    match find_next_stld cs' pid with
    | None => (f, true, pid::dones)
    | Some (inl lid) => (remove_fdef lid (subst_fdef lid v1 f), true, dones)
    | Some (inr (sid2, v2)) => (f, true, pid::dones)
    end
end.

(* do las/laa/sas in block [b] *)
Definition elim_stld_block (f:fdef) (b: block) (pid:id) (dones:list id) 
  : fdef * bool * list id :=
match b with
| block_intro _ _ cs _=> elim_stld_cmds f cs pid dones 
end.

Definition ElimStld := mkIterPass (list id) id elim_stld_block nil.

Parameter does_stld_elim : unit -> bool.

(* remove dead stores *)
Fixpoint elim_dead_st_cmds (cs:cmds) (pid:id) : cmds :=
match cs with
| nil => nil
| insn_store sid _ _ (value_id qid) _ as c :: cs' =>
    if (id_dec pid qid) then elim_dead_st_cmds cs' pid
    else c :: elim_dead_st_cmds cs' pid
| c::cs' => c :: elim_dead_st_cmds cs' pid
end.

Definition elim_dead_st_block (pid:id) (b: block) : block :=
match b with
| block_intro l0 ps cs tmn => block_intro l0 ps (elim_dead_st_cmds cs pid) tmn
end.

Definition elim_dead_st_fdef (pid:id) (f:fdef) : fdef :=
let '(fdef_intro fh bs) := f in
fdef_intro fh (List.map (elim_dead_st_block pid) bs).

(* in function [f], given its reachable blocks [rd], CFG represented by
   successors [succs] and predecessors [preds]. Do the following in sequence
   1) find a promotable alloca
   2) insert phinodes
   3) las/laa/sas
   4) dse
   5) dae
   [dones] tracks the allocas checked and seen
*)
Definition macro_mem2reg_fdef_iter (f:fdef) (rd:list l) 
  (succs preds:ATree.t (list l)) (dones:list id) : fdef * bool * list id := 
match getEntryBlock f with
| Some (block_intro _ _ cs _) =>
    match find_promotable_alloca f cs dones with
    | None => (f, false, dones)
    | Some (pid, ty, num, al) =>
        let f1 := phinodes_placement rd pid ty al succs preds f in
        let '(f2, _) :=
          if does_stld_elim tt then
            IterationPass.iter ElimStld pid rd f1
          else (f1, nil)
        in
        let f3 :=
          if load_in_fdef pid f2 then f2 else elim_dead_st_fdef pid f2
        in
        (if used_in_fdef pid f3 then f3 else remove_fdef pid f3,
         true, pid::dones)
    end
| _ => (f, false, dones)
end.

(* one step of macro-optimization, after each step, we check if
   anything was changed, if not, we stop.
   return a sum: left means unfinished; right means done
*)
Definition macro_mem2reg_fdef_step (rd:list l) (succs preds:ATree.t (list l))
  (st:fdef * list id) : (fdef * list id) + (fdef * list id) :=
let '(f, dones) := st in
let '(f1, changed1, dones1) :=
      macro_mem2reg_fdef_iter f rd succs preds dones in
if changed1 then inr _ (f1, dones1) else inl _ (f1, dones1).

(* the following does phinode elimination.

   pruning when does_dead_phi_elim sets
   not prunning by default
*)
Definition valueInListValueB (v0:value) (vs:list value) : bool :=
List.fold_left (fun acc v => acc || valueEqB v0 v) vs false.

Fixpoint remove_redundancy (acc:list value) (vs:list value) : list value :=
match vs with
| nil => acc
| v::vs' => 
    if (valueInListValueB v acc) then remove_redundancy acc vs'
    else remove_redundancy (v::acc) vs'
end.

Parameter does_dead_phi_elim : unit -> bool.

Definition eliminate_phi (f:fdef) (pn:phinode): fdef * bool:=
let '(insn_phi pid _ vls) := pn in 
let ndpvs := 
  remove_redundancy nil (value_id pid::List.map fst vls) 
in
match ndpvs with
| value_id id1 as v1::v2::nil =>
    if (id_dec pid id1) then 
      (* if v1 is pid, then v2 cannot be pid*)
      (remove_fdef pid (subst_fdef pid v2 f), true)
    else  
      (* if v1 isnt pid, then v2 must be pid*)
      (remove_fdef pid (subst_fdef pid v1 f), true)
| value_const _ as v1::_::nil =>
    (* if v1 is const, then v2 must be pid*)
    (remove_fdef pid (subst_fdef pid v1 f), true)
| v1::nil => 
    (* v1 must be pid, so pn:= pid = phi [pid, ..., pid] *)
    (remove_fdef pid f, true)
| _ => 
   if does_dead_phi_elim tt then
      if used_in_fdef pid f then (f, false) else (remove_fdef pid f, true)
   else (f, false)
end.

Fixpoint eliminate_phis (f:fdef) (ps: phinodes): fdef * bool :=
match ps with
| nil => (f, false)
| p::ps' =>
    let '(f', changed) := eliminate_phi f p in
    if changed then (f', true) else eliminate_phis f' ps'
end.

Definition eliminate_block (f:fdef) (b: block) (ut:unit) (dones:list id) 
  : fdef * bool * list id :=
match b with
| block_intro _ ps _ _=> (eliminate_phis f ps, dones)
end.

Definition ElimPhi := mkIterPass (list id) unit eliminate_block nil.

Parameter does_phi_elim : unit -> bool.
Parameter does_macro_m2r : unit -> bool.

Parameter is_llvm_dbg_declare : id -> bool.

(* remove allocas for dbg intrinsics, which prevents from identifying 
   promotable allocas, should be extended to remove lifetime intrinsics too.
 *)
Definition remove_dbg_declare (pid:id) (f:fdef) : fdef :=
let uses := find_uses_in_fdef pid f in
let re :=List.fold_left
  (fun acc i =>
   match acc with
   | None => None
   | Some (bldst, ocid, orid) =>
       match i with 
       | insn_cmd (insn_load _ _ _ _) => Some (true, ocid, orid)
       | insn_cmd (insn_store _ _ v _ _) => 
           if valueEqB v (value_id pid) then None else Some (true, ocid, orid)
       | insn_cmd (insn_cast cid castop_bitcast _ _ _) =>
           match ocid with
           | Some _ => 
               (* not remove if used by multiple bitcast *)
               None
           | None =>
               match find_uses_in_fdef cid f with
               | insn_cmd 
                   (insn_call rid _ _ _ _ (value_const (const_gid _ fid)) _)
                   ::nil =>
                   if is_llvm_dbg_declare fid then 
                     Some (bldst, Some cid, Some rid)
                   else None
               | _ => None
               end
           end
       | _ => None
       end
   end)
  uses (Some (false, None, None)) in
match re with
| Some (true, Some cid, Some rid) => 
    (* if pid is used by ld/st and a simple dbg *)
    remove_fdef cid (remove_fdef rid f)
| _ => f
end.

Fixpoint remove_dbg_declares (f:fdef) (cs:cmds) : fdef :=
match cs with
| nil => f
| insn_alloca pid _ _ _ :: cs' =>
    remove_dbg_declares (remove_dbg_declare pid f) cs'
| _ :: cs' => remove_dbg_declares f cs'
end.

(* The two kinds of mem2reg algorithm for each function
   1) when does_macro_m2r tt = true
      A pipelined algorithm based on a group of primitives, which is
      fully verified.
   2) when does_macro_m2r tt = false
      A algorithm based on dom-tree traversal, and not verified
*)
Definition mem2reg_fdef (f:fdef) : fdef :=
match getEntryBlock f, reachablity_analysis f with
| Some (block_intro root _ cs _), Some rd =>
  if print_reachablity rd then
    let '(f1, _) :=
      if (does_macro_m2r tt) then
        let f0 := remove_dbg_declares f cs in
        let succs := successors f0 in
        let preds := XATree.make_predecessors succs in
        SafePrimIter.iterate _ 
          (macro_mem2reg_fdef_step rd succs preds) (f0, nil) 
      else
        let b := bound_fdef f in
        let dts := AlgDom.dom_query f in
        let chains := compute_sdom_chains dts rd in
        let dt :=
          fold_left
            (fun acc elt =>
             let '(_, chain):=elt in
             create_dtree_from_chain acc chain)
            chains (DT_node root DT_nil) in
        if print_dominators b dts && print_dtree dt then
           SafePrimIter.iterate _ (mem2reg_fdef_step dt rd) (f, nil)
        else (f, nil)
    in
    let f2 :=
      if does_phi_elim tt 
      then fst (IterationPass.iter ElimPhi tt rd f1) else f1 in
    match fix_temporary_fdef f2 with
    | Some f' => f'
    | None => f
    end
  else f
| _, _ => f
end.

(* the top entry *)
Definition run (m:module) : module :=
let '(module_intro los nts ps) := m in
module_intro los nts
  (List.map (fun p =>
             match p with
             | product_fdef f => product_fdef (mem2reg_fdef f)
             | _ => p
             end) ps).

