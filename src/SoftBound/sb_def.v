Add LoadPath "../ssa/ott".
Add LoadPath "../ssa/monads".
Add LoadPath "../ssa".
Add LoadPath "../ssa/compcert".
Add LoadPath "../../../theory/metatheory_8.3".
Add LoadPath "../TV".
Require Import ssa_def.
Require Import ssa_lib.
Require Import trace.
Require Import Memory.
Require Import genericvalues.
Require Import assoclist.
Require Import ssa_dynamic.
Require Import Integers.
Require Import Values.
Require Import Coqlib.
Require Import monad.
Require Import Metatheory.
Require Import symexe_def.
Require Import Znumtheory.

Export LLVMsyntax.
Export LLVMgv.

Module SoftBound.

Record metadata : Type := mkMD {
  md_base : GenericValue; md_bound : GenericValue
}.

Definition rmetadata := list (id*metadata).

Inductive result : Set :=
| rok : result 
| rabort : result
| rerror : result
.  

Definition base2GV (TD:TargetData) (b:mblock) : GenericValue :=
ptr2GV TD (Vptr b (Int.repr 31 0)).

Definition bound2GV (TD:TargetData) (b:mblock) (s:sz) n : GenericValue :=
ptr2GV TD (Vptr b (Int.repr 31 ((Size.to_Z s)*n))).

Fixpoint get_const_metadata (c:const) : option (const*const) :=
match c with
| const_gid t gid => 
    match t with
    | typ_function _ _ => Some (c, c)
    | _ => Some (c, const_gep false c 
             (Cons_list_const (const_int Size.ThirtyTwo 1%Z) Nil_list_const))
    end
| const_gep _ pc _ => get_const_metadata pc
| _ => None
end.

Definition get_reg_metadata TD M gl (rm:rmetadata) (v:value) 
  : option metadata :=
  match v with
  | value_id pid => lookupAL _ rm pid
  | value_const c => 
      match get_const_metadata c with
      | Some (bc, ec) => 
          do gvb <- const2GV TD M gl bc;
          do gve <- const2GV TD M gl ec;
          ret (mkMD gvb gve)
      | None => None
      end
  end.

Definition assert_mptr (TD:TargetData) (t:typ) (ptr:GenericValue) (md:metadata)
  : Prop :=
  let 'mkMD base bound := md in
  match (GV2ptr TD (getPointerSize TD) ptr,
         GV2ptr TD (getPointerSize TD) base,
         GV2ptr TD (getPointerSize TD) bound,
         getTypeAllocSize TD t) with
  | (Some (Vptr pb pofs), Some (Vptr bb bofs), Some (Vptr eb eofs), Some tsz) =>
      zeq pb bb /\ zeq bb eb /\
      zle (Integers.Int.unsigned 31 bofs) (Integers.Int.unsigned 31 pofs) /\ 
      zle (Integers.Int.unsigned 31 pofs) 
          (Integers.Int.unsigned 31 eofs + Z_of_nat tsz)
  | _ => False
  end.  

Definition SELECT TD Mem v0 v1 v2 lc gl : option GenericValue :=
  match (getOperandValue TD Mem v0 lc gl, getOperandValue TD Mem v1 lc gl,
         getOperandValue TD Mem v2 lc gl) with
  | (Some cond, Some gv1, Some gv2) => 
      Some (if isGVZero TD cond then gv2 else gv1)
  | _ => None
  end.

Definition prop_reg_metadata lc rmd pid gvp (md:metadata) : 
    GVMap * rmetadata  :=
  (updateAddAL _ lc pid gvp, updateAddAL _ rmd pid md).

Definition mmetadata := Values.block -> int32 -> option metadata.

Definition get_mem_metadata TD MM (gv:GenericValue) : option metadata :=
  match (GV2ptr TD (getPointerSize TD) gv) with
  | Some (Vptr b ofs) => MM b ofs
  | _ => None
  end.

Definition set_mem_metadata TD MM (gv:GenericValue) (md:metadata) 
  : mmetadata :=
  match (GV2ptr TD (getPointerSize TD) gv) with
  | Some (Vptr b ofs) => 
     fun b1 => fun ofs1 =>
       if zeq b1 b && Integers.Int.eq_dec 31 ofs ofs1 then Some md 
       else MM b1 ofs1
  | _ => MM
  end.

Inductive dbCmd : TargetData -> GVMap -> 
                  GVMap -> rmetadata ->list mblock -> mem -> mmetadata ->
                  cmd -> 
                  GVMap -> rmetadata ->list mblock -> mem -> mmetadata ->
                  trace -> result -> Prop :=
| dbBop: forall TD rm lc gl id bop sz v1 v2 gv3 Mem MM als,
  BOP TD Mem lc gl bop sz v1 v2 = Some gv3 ->
  dbCmd TD gl lc rm als Mem MM (insn_bop id bop sz v1 v2)
    (updateAddAL _ lc id gv3) rm als Mem MM trace_nil rok

| dbBop_error: forall TD rm lc gl id bop sz v1 v2 Mem MM als,
  BOP TD Mem lc gl bop sz v1 v2 = None ->
  dbCmd TD gl lc rm als Mem MM (insn_bop id bop sz v1 v2) lc rm als Mem MM 
    trace_nil rerror

| dbFBop: forall TD rm lc gl id fbop fp v1 v2 gv3 Mem MM als,
  FBOP TD Mem lc gl fbop fp v1 v2 = Some gv3 ->
  dbCmd TD gl lc rm als Mem MM (insn_fbop id fbop fp v1 v2)
    (updateAddAL _ lc id gv3) rm als Mem MM trace_nil rok

| dbFBop_error: forall TD rm lc gl id fbop fp v1 v2 Mem MM als,
  FBOP TD Mem lc gl fbop fp v1 v2 = None ->
  dbCmd TD gl lc rm als Mem MM (insn_fbop id fbop fp v1 v2) lc rm als Mem MM
    trace_nil rerror

| dbExtractValue : forall TD rm lc gl id t v gv gv' Mem MM als idxs,
  getOperandValue TD Mem v lc gl = Some gv ->
  extractGenericValue TD t gv idxs = Some gv' ->
  dbCmd TD gl lc rm als Mem MM (insn_extractvalue id t v idxs)
    (updateAddAL _ lc id gv') rm als Mem MM trace_nil rok 

| dbExtractValue_error : forall TD rm lc gl id t v gv Mem MM als idxs,
  getOperandValue TD Mem v lc gl = None ->
  extractGenericValue TD t gv idxs = None ->
  dbCmd TD gl lc rm als Mem MM (insn_extractvalue id t v idxs) lc rm als Mem MM
    trace_nil rerror 

| dbInsertValue : forall TD rm lc gl id t v t' v' gv gv' gv'' idxs Mem MM als,
  getOperandValue TD Mem v lc gl = Some gv ->
  getOperandValue TD Mem v' lc gl = Some gv' ->
  insertGenericValue TD t gv idxs t' gv' = Some gv'' ->
  dbCmd TD gl lc rm als Mem MM (insn_insertvalue id t v t' v' idxs)
    (updateAddAL _ lc id gv'') rm als Mem MM trace_nil rok

| dbInsertValue_error : forall TD rm lc gl id t v t' v' gv gv' idxs Mem MM als,
  getOperandValue TD Mem v lc gl = Some gv ->
  getOperandValue TD Mem v' lc gl = Some gv' ->
  insertGenericValue TD t gv idxs t' gv' = None ->
  dbCmd TD gl lc rm als Mem MM (insn_insertvalue id t v t' v' idxs) lc rm als Mem
    MM trace_nil rerror

| dbMalloc : forall TD rm lc gl id t v gn align Mem MM als Mem' tsz mb lc' rm' n,
  getTypeAllocSize TD t = Some tsz ->
  getOperandValue TD Mem v lc gl = Some gn ->
  malloc TD Mem tsz gn align = Some (Mem', mb) ->
  GV2int TD Size.ThirtyTwo gn = Some n ->
  prop_reg_metadata lc rm id (blk2GV TD mb) (mkMD (base2GV TD mb) 
    (bound2GV TD mb tsz n)) = (lc',rm') ->
  dbCmd TD gl lc rm als Mem MM (insn_malloc id t v align) lc' rm' als Mem' MM
    trace_nil rok

| dbMalloc_error : forall TD rm lc gl id t v gn align Mem MM als tsz,
  getTypeAllocSize TD t = Some tsz ->
  getOperandValue TD Mem v lc gl = Some gn ->
  malloc TD Mem tsz gn align = None ->
  dbCmd TD gl lc rm als Mem MM (insn_malloc id t v align) lc rm als Mem MM
    trace_nil rerror

| dbFree : forall TD rm lc gl fid t v Mem MM als Mem' mptr,
  getOperandValue TD Mem v lc gl = Some mptr ->
  free TD Mem mptr = Some Mem'->
  dbCmd TD gl lc rm als Mem MM (insn_free fid t v) lc rm als Mem' MM trace_nil 
    rok

| dbFree_error : forall TD rm lc gl fid t v Mem MM als mptr,
  getOperandValue TD Mem v lc gl = Some mptr ->
  free TD Mem mptr = None ->
  dbCmd TD gl lc rm als Mem MM (insn_free fid t v) lc rm als Mem MM trace_nil 
    rerror

| dbAlloca : forall TD rm lc gl id t v gn align Mem MM als Mem' tsz mb lc' rm' n,
  getTypeAllocSize TD t = Some tsz ->
  getOperandValue TD Mem v lc gl = Some gn ->
  malloc TD Mem tsz gn align = Some (Mem', mb) ->
  GV2int TD Size.ThirtyTwo gn = Some n ->
  prop_reg_metadata lc rm id (blk2GV TD mb) (mkMD (base2GV TD mb) 
    (bound2GV TD mb tsz n)) = (lc', rm') ->
  dbCmd TD gl lc rm als Mem MM (insn_alloca id t v align) lc' rm' (mb::als) Mem' 
    MM trace_nil rok

| dbAlloca_error : forall TD rm lc gl id t v gn align Mem MM als tsz,
  getTypeAllocSize TD t = Some tsz ->
  getOperandValue TD Mem v lc gl = Some gn ->
  malloc TD Mem tsz gn align = None ->
  dbCmd TD gl lc rm als Mem MM (insn_alloca id t v align) lc rm als Mem MM
    trace_nil rerror

| dbLoad_nptr : forall TD rm lc gl id t vp align Mem MM als gvp md gv,
  get_reg_metadata TD Mem gl rm vp = Some md ->
  getOperandValue TD Mem vp lc gl = Some gvp ->
  assert_mptr TD t gvp md ->
  mload TD Mem gvp t align = Some gv ->
  ~ isPointerTyp t ->
  dbCmd TD gl lc rm als Mem MM (insn_load id t vp align) (updateAddAL _ lc id gv)
    rm als Mem MM trace_nil rok

| dbLoad_ptr : forall TD rm lc gl id t vp align Mem MM als gvp md gv md' lc' rm',
  get_reg_metadata TD Mem gl rm vp = Some md ->
  getOperandValue TD Mem vp lc gl = Some gvp ->
  assert_mptr TD t gvp md ->
  mload TD Mem gvp t align = Some gv ->
  isPointerTyp t ->
  get_mem_metadata TD MM gvp = Some md' -> 
  prop_reg_metadata lc rm id gv md' = (lc', rm') ->
  dbCmd TD gl lc rm als Mem MM (insn_load id t vp align) lc' rm' als Mem MM 
    trace_nil rok

| dbLoad_error1 : forall TD rm lc gl id t vp align Mem MM als gvp,
  getOperandValue TD Mem vp lc gl = Some gvp ->
  GV2ptr TD (getPointerSize TD) gvp = None ->
  dbCmd TD gl lc rm als Mem MM (insn_load id t vp align) lc rm als Mem MM 
    trace_nil rerror

| dbLoad_error2 : forall TD rm lc gl id t vp align Mem MM als gvp b ofs,
  getOperandValue TD Mem vp lc gl = Some gvp ->
  GV2ptr TD (getPointerSize TD) gvp = Some (Vptr b ofs) ->
  typ2memory_chunk t = None ->
  dbCmd TD gl lc rm als Mem MM (insn_load id t vp align) lc rm als Mem MM 
    trace_nil rerror

| dbLoad_error3 : forall TD rm lc gl id t vp align Mem MM als gvp b ofs c,
  getOperandValue TD Mem vp lc gl = Some gvp ->
  GV2ptr TD (getPointerSize TD) gvp = Some (Vptr b ofs) ->
  typ2memory_chunk t = Some c ->
  ~ (align_chunk c | (Int.unsigned 31 ofs)) ->
  dbCmd TD gl lc rm als Mem MM (insn_load id t vp align) lc rm als Mem MM 
    trace_nil rerror

| dbLoad_abort : forall TD rm lc gl id t vp align Mem MM als gvp md,
  get_reg_metadata TD Mem gl rm vp = Some md ->
  getOperandValue TD Mem vp lc gl = Some gvp ->
  ~ assert_mptr TD t gvp md ->
  dbCmd TD gl lc rm als Mem MM (insn_load id t vp align) lc rm als Mem MM
    trace_nil rabort

| dbStore_nptr : forall TD rm lc gl sid t v vp align Mem MM als gv gvp md Mem',
  get_reg_metadata TD Mem gl rm vp = Some md ->
  getOperandValue TD Mem v lc gl = Some gv ->
  getOperandValue TD Mem vp lc gl = Some gvp ->
  assert_mptr TD t gvp md ->
  mstore TD Mem gvp t gv align = Some Mem' ->
  ~ isPointerTyp t ->
  dbCmd TD gl lc rm als Mem MM (insn_store sid t v vp align) lc rm als Mem' MM
    trace_nil rok

| dbStore_ptr : forall TD rm lc gl sid t v vp align Mem MM als gv gvp md Mem' 
                       md' MM',
  get_reg_metadata TD Mem gl rm vp = Some md ->
  getOperandValue TD Mem v lc gl = Some gv ->
  getOperandValue TD Mem vp lc gl = Some gvp ->
  assert_mptr TD t gvp md ->
  mstore TD Mem gvp t gv align = Some Mem' ->
  isPointerTyp t ->
  get_reg_metadata TD Mem gl rm v = Some md' ->
  set_mem_metadata TD MM gvp md' = MM' -> 
  dbCmd TD gl lc rm als Mem MM (insn_store sid t v vp align) lc rm als Mem' MM'
    trace_nil rok

| dbStore_error1 : forall TD rm lc gl sid t v vp align Mem MM als gv gvp,
  getOperandValue TD Mem v lc gl = Some gv ->
  getOperandValue TD Mem vp lc gl = Some gvp ->
  GV2ptr TD (getPointerSize TD) gvp = None ->
  dbCmd TD gl lc rm als Mem MM (insn_store sid t v vp align) lc rm als Mem MM
    trace_nil rerror

| dbStore_error2 : forall TD rm lc gl sid t v vp align Mem MM als gv gvp b ofs,
  getOperandValue TD Mem v lc gl = Some gv ->
  getOperandValue TD Mem vp lc gl = Some gvp ->
  GV2ptr TD (getPointerSize TD) gvp = Some (Vptr b ofs) ->
  typ2memory_chunk t = None \/ GV2val TD gvp = None ->
  dbCmd TD gl lc rm als Mem MM (insn_store sid t v vp align) lc rm als Mem MM
    trace_nil rerror

| dbStore_error3 : forall TD rm lc gl sid t v vp align Mem MM als gv gvp b ofs
                          c v0,
  getOperandValue TD Mem v lc gl = Some gv ->
  getOperandValue TD Mem vp lc gl = Some gvp ->
  GV2ptr TD (getPointerSize TD) gvp = Some (Vptr b ofs) ->
  typ2memory_chunk t = Some c ->
  GV2val TD gvp = Some v0 ->
  ~ (align_chunk c | (Int.unsigned 31 ofs)) ->
  dbCmd TD gl lc rm als Mem MM (insn_store sid t v vp align) lc rm als Mem MM
    trace_nil rerror

| dbStore_abort : forall TD rm lc gl sid t v vp align Mem MM als gv gvp md,
  get_reg_metadata TD Mem gl rm vp = Some md ->
  getOperandValue TD Mem v lc gl = Some gv ->
  getOperandValue TD Mem vp lc gl = Some gvp ->
  ~ assert_mptr TD t gvp md ->
  dbCmd TD gl lc rm als Mem MM (insn_store sid t v vp align) lc rm als Mem MM 
    trace_nil
    rabort

| dbGEP : forall TD rm lc gl id inbounds t vp idxs vidxs gvp' Mem MM als gvp md 
                 lc' rm',
  get_reg_metadata TD Mem gl rm vp = Some md ->
  getOperandValue TD Mem vp lc gl = Some gvp ->
  values2GVs TD Mem idxs lc gl = Some vidxs ->
  GEP TD t gvp vidxs inbounds = Some gvp' ->
  prop_reg_metadata lc rm id gvp' md = (lc', rm') ->
  dbCmd TD gl lc rm als Mem MM (insn_gep id inbounds t vp idxs) lc' rm' als Mem 
    MM trace_nil rok 

| dbGEP_error : forall TD rm lc gl id inbounds t v idxs vidxs mp Mem MM als,
  getOperandValue TD Mem v lc gl = Some mp ->
  values2GVs TD Mem idxs lc gl = Some vidxs ->
  GEP TD t mp vidxs inbounds = None ->
  dbCmd TD gl lc rm als Mem MM (insn_gep id inbounds t v idxs) lc rm als Mem MM
    trace_nil rerror

| dbTrunc : forall TD rm lc gl id truncop t1 v1 t2 gv2 Mem MM als,
  TRUNC TD Mem lc gl truncop t1 v1 t2 = Some gv2 ->
  dbCmd TD gl lc rm als Mem MM (insn_trunc id truncop t1 v1 t2) 
    (updateAddAL _ lc id gv2) rm als Mem MM trace_nil rok

| dbTrunc_error : forall TD rm lc gl id truncop t1 v1 t2 Mem MM als,
  TRUNC TD Mem lc gl truncop t1 v1 t2 = None ->
  dbCmd TD gl lc rm als Mem MM (insn_trunc id truncop t1 v1 t2) lc rm als Mem MM
    trace_nil rerror

| dbExt : forall TD rm lc gl id extop t1 v1 t2 gv2 Mem MM als,
  EXT TD Mem lc gl extop t1 v1 t2 = Some gv2 ->
  dbCmd TD gl lc rm als Mem MM (insn_ext id extop t1 v1 t2)
    (updateAddAL _ lc id gv2) rm als Mem MM trace_nil rok

| dbExt_error : forall TD rm lc gl id extop t1 v1 t2 Mem MM als,
  EXT TD Mem lc gl extop t1 v1 t2 = None ->
  dbCmd TD gl lc rm als Mem MM (insn_ext id extop t1 v1 t2) lc rm als Mem MM
    trace_nil rerror

| dbBitcast_nptr : forall TD rm lc gl id t1 v1 t2 gv2 Mem MM als,
  CAST TD Mem lc gl castop_bitcast t1 v1 t2 = Some gv2 ->
  ~ isPointerTyp t1 ->
  dbCmd TD gl lc rm als Mem MM (insn_cast id castop_bitcast t1 v1 t2)
     (updateAddAL _ lc id gv2) rm als Mem MM trace_nil rok

| dbBitcast_ptr : forall TD rm lc gl id t1 v1 t2 gv2 Mem MM als lc' md rm',
  CAST TD Mem lc gl castop_bitcast t1 v1 t2 = Some gv2 ->
  isPointerTyp t1 ->
  get_reg_metadata TD Mem gl rm v1 = Some md ->
  prop_reg_metadata lc rm id gv2 md = (lc', rm') ->
  dbCmd TD gl lc rm als Mem MM (insn_cast id castop_bitcast t1 v1 t2) lc' rm' 
    als Mem MM trace_nil rok

| dbInttoptr : forall TD rm lc gl id t1 v1 t2 gv2 Mem MM als lc' rm',
  CAST TD Mem lc gl castop_inttoptr t1 v1 t2 = Some gv2 ->
  prop_reg_metadata lc rm id gv2 (mkMD null null) = (lc', rm') ->
  dbCmd TD gl lc rm als Mem MM (insn_cast id castop_inttoptr t1 v1 t2) lc' rm' 
    als Mem MM trace_nil rok

| dbOtherCast : forall TD rm lc gl id castop t1 v1 t2 gv2 Mem MM als,
  CAST TD Mem lc gl castop t1 v1 t2 = Some gv2 ->
  castop <> castop_bitcast /\ castop <> castop_inttoptr ->
  dbCmd TD gl lc rm als Mem MM (insn_cast id castop t1 v1 t2)
     (updateAddAL _ lc id gv2) rm als Mem MM trace_nil rok

| dbCast_error : forall TD rm lc gl id castop t1 v1 t2 Mem MM als,
  CAST TD Mem lc gl castop t1 v1 t2 = None ->
  dbCmd TD gl lc rm als Mem MM (insn_cast id castop t1 v1 t2) lc rm als Mem MM
    trace_nil rerror

| dbIcmp : forall TD rm lc gl id cond t v1 v2 gv3 Mem MM als,
  ICMP TD Mem lc gl cond t v1 v2 = Some gv3 ->
  dbCmd TD gl lc rm als Mem MM (insn_icmp id cond t v1 v2)
    (updateAddAL _ lc id gv3) rm als Mem MM trace_nil rok

| dbIcmp_error : forall TD rm lc gl id cond t v1 v2 Mem MM als,
  ICMP TD Mem lc gl cond t v1 v2 = None ->
  dbCmd TD gl lc rm als Mem MM (insn_icmp id cond t v1 v2) lc rm als Mem MM 
    trace_nil rerror

| dbFcmp : forall TD rm lc gl id fcond fp v1 v2 gv3 Mem MM als,
  FCMP TD Mem lc gl fcond fp v1 v2 = Some gv3 ->
  dbCmd TD gl lc rm als Mem MM (insn_fcmp id fcond fp v1 v2)
    (updateAddAL _ lc id gv3) rm als Mem MM trace_nil rok

| dbFcmp_error : forall TD rm lc gl id fcond fp v1 v2 Mem MM als,
  FCMP TD Mem lc gl fcond fp v1 v2 = None ->
  dbCmd TD gl lc rm als Mem MM (insn_fcmp id fcond fp v1 v2) lc rm als Mem MM 
    trace_nil rerror

| dbSelect_nptr : forall TD rm lc gl id v0 t v1 v2 Mem MM als gv,
  SELECT TD Mem v0 v1 v2 lc gl = Some gv ->
  ~ isPointerTyp t ->
  dbCmd TD gl lc rm als Mem MM (insn_select id v0 t v1 v2) 
    (updateAddAL _ lc id gv) rm als Mem MM trace_nil rok

| dbSelect_ptr : forall TD rm lc gl id v0 t v1 v2 Mem MM als gv md1 md2 cond lc' 
                 rm',
  SELECT TD Mem v0 v1 v2 lc gl = Some gv ->
  isPointerTyp t ->
  get_reg_metadata TD Mem gl rm v1 = Some md1 ->
  get_reg_metadata TD Mem gl rm v2 = Some md2 ->
  getOperandValue TD Mem v0 lc gl = Some cond ->
  (if isGVZero TD cond then 
    prop_reg_metadata lc rm id gv md2
  else
    prop_reg_metadata lc rm id gv md1)
    = (lc', rm') ->
  dbCmd TD gl lc rm als Mem MM (insn_select id v0 t v1 v2) lc' rm' als Mem MM 
    trace_nil rok

| dbSelect_error : forall TD rm lc gl id v0 t v1 v2 Mem MM als,
  SELECT TD Mem v0 v1 v2 lc gl = None ->
  dbCmd TD gl lc rm als Mem MM (insn_select id v0 t v1 v2) lc rm als Mem MM
    trace_nil rerror

| dbLib : forall TD lc gl rid noret tailc ft fid rm MM
                          lp rt Mem oresult Mem' lc' als r,
  SimpleSE.callLib Mem fid (params2GVs TD Mem lp lc gl) = 
    Some (oresult, Mem', r) ->
  LLVMopsem.exCallUpdateLocals noret rid oresult lc = Some lc' ->
  dbCmd TD gl
    lc rm als Mem MM
    (insn_call rid noret tailc rt (value_const (const_gid ft fid)) lp)
    lc' rm als Mem' MM trace_nil rok

| dbLib_error : forall TD lc gl rid noret tailc ft fid rm MM
                          lp rt Mem oresult Mem' als r,
  SimpleSE.callLib Mem fid (params2GVs TD Mem lp lc gl) = 
    Some (oresult, Mem', r) ->
  dbCmd TD gl
    lc rm als Mem MM
    (insn_call rid noret tailc rt (value_const (const_gid ft fid)) lp)
    lc rm als Mem' MM trace_nil rerror
.

Definition is_error r :=
match r with
| rok => False
| _ => True
end.

Inductive dbCmds : TargetData -> GVMap ->
                   GVMap -> rmetadata -> list mblock -> mem -> mmetadata ->
                   list cmd -> 
                   GVMap -> rmetadata -> list mblock -> mem -> mmetadata ->
                   trace -> result -> Prop :=
| dbCmds_nil : forall TD lc als gl rm Mem MM, 
    dbCmds TD gl lc rm als Mem MM nil lc rm als Mem MM trace_nil rok

| dbCmds_cons : forall TD c cs gl lc1 rm1 als1 Mem1 MM1 t1 t2 lc2 rm2 als2 Mem2
                       MM2 lc3 rm3 als3 Mem3 MM3 r,
    dbCmd TD gl lc1 rm1 als1 Mem1 MM1 c lc2 rm2 als2 Mem2 MM2 t1 rok ->
    dbCmds TD gl lc2 rm2 als2 Mem2 MM2 cs lc3 rm3 als3 Mem3 MM3 t2 r ->
    dbCmds TD gl lc1 rm1 als1 Mem1 MM1 (c::cs) lc3 rm3 als3 Mem3 MM3
      (trace_app t1 t2) r

| dbCmds_cons_error : forall TD c cs gl lc1 rm1 als1 Mem1 MM1 t1 r lc2 rm2 als2 
                     Mem2 MM2,
    dbCmd TD gl lc1 rm1 als1 Mem1 MM1 c lc2 rm2 als2 Mem2 MM2 t1 r ->
    is_error r ->
    dbCmds TD gl lc1 rm1 als1 Mem1 MM1 (c::cs) lc2 rm2 als2 Mem2 MM2 t1 r
.

Record ExecutionContext : Type := mkEC
  { ec_curBB : block;  
    ec_locals : GVMap;  
    ec_rmd : rmetadata;
    ec_als : list mblock}.

Record State : Type := mkState 
  { st_frame : ExecutionContext;  
    st_mem : mem; 
    st_mmd : mmetadata }.

Definition callUpdateLocals (TD:TargetData) (M:mem) (noret:bool) (rid:id) 
  (oResult:option value) (rm rm':rmetadata) (lc lc' gl:GVMap) 
  : option (GVMap * rmetadata):=
    match noret with
    | false =>
        match oResult with
        | None => None
        | Some Result => 
          match (getOperandValue TD M Result lc' gl) with 
          | Some gr => 
              match get_reg_metadata TD M gl rm' Result with
              | None => Some (updateAddAL _ lc rid gr, rm)
              | Some md' => Some (updateAddAL _ lc rid gr, 
                                  updateAddAL _ rm rid md')
              end
          | None => None
          end
        end
    | true => Some (lc,rm)
    end.

Fixpoint initRmetadata_aux TD Mem gl (la:args) (lp:params) (rm accum:rmetadata) 
  : option rmetadata :=
match (la, lp) with
| ((t,id)::la', (_,v)::lp') =>
    if isPointerTypB t then
      match get_reg_metadata TD Mem gl rm v with 
      | Some md => 
          initRmetadata_aux TD Mem gl la' lp' rm (updateAddAL _ accum id md)
      | None => None
      end
    else initRmetadata_aux TD Mem gl la' lp' rm accum
| (nil, nil) => Some accum
| _ => None
end.  

Definition initRmetadata TD Mem gl (la:args) (lp:params) (rm:rmetadata) 
  : option rmetadata := 
  initRmetadata_aux TD Mem gl la lp rm nil.

Inductive dbCall : system -> TargetData -> list product -> GVMap ->      
                   GVMap -> GVMap -> rmetadata -> mem -> mmetadata ->
                   cmd -> 
                   GVMap -> rmetadata -> mem -> mmetadata ->
                   trace -> result -> Prop :=
| dbCall_internal : forall S TD Ps lc rm gl fs rid noret tailc rt fv lp
                Rid oResult tr lc' rm' Mem MM Mem' MM' als' Mem'' B' lc'' rm'',
  dbFdef fv rt lp S TD Ps lc rm gl fs Mem MM lc' rm' als' Mem' MM' B' Rid 
    oResult tr rok ->
  free_allocas TD Mem' als' = Some Mem'' ->
  SimpleSE.isCall (insn_call rid noret tailc rt fv lp) = true ->
  callUpdateLocals TD Mem'' noret rid oResult rm rm' lc lc' gl = 
    Some (lc'',rm'') ->
  dbCall S TD Ps fs gl lc rm Mem MM (insn_call rid noret tailc rt fv lp) lc'' 
    rm'' Mem'' MM' tr rok

| dbCall_external : forall S TD Ps lc gl fs rid noret tailc fv fid 
                          lp rt la Mem MM oresult Mem' lc' rm,
  (* only look up the current module for the time being, 
     do not support linkage. 
     FIXME: should add excall to trace
  *)
  LLVMopsem.lookupExFdecViaGV TD Mem Ps gl lc fs fv = 
    Some (fdec_intro (fheader_intro rt fid la)) ->
  LLVMopsem.callExternalFunction Mem fid (params2GVs TD Mem lp lc gl) = 
    (oresult, Mem') ->
  SimpleSE.isCall (insn_call rid noret tailc rt fv lp) = true ->
  LLVMopsem.exCallUpdateLocals noret rid oresult lc = Some lc' ->
  dbCall S TD Ps fs gl lc rm Mem MM (insn_call rid noret tailc rt fv lp) lc' rm 
    Mem' MM trace_nil rok

| dbCall_internal_error1 : forall S TD Ps lc rm gl fs rid noret tailc rt fv lp
                       Rid oResult tr lc' rm' Mem MM Mem' MM' als' B',
  dbFdef fv rt lp S TD Ps lc rm gl fs Mem MM lc' rm' als' Mem' MM' B' Rid oResult
    tr rok ->
  free_allocas TD Mem' als' = None ->
  dbCall S TD Ps fs gl lc rm Mem MM (insn_call rid noret tailc rt fv lp) lc rm 
    Mem' MM' tr rerror

| dbCall_internal_error2 : forall S TD Ps lc rm gl fs rid noret tailc rt fv lp
                       Rid oResult tr lc' rm' Mem MM Mem' MM' als' B' r,
  dbFdef fv rt lp S TD Ps lc rm gl fs Mem MM lc' rm' als' Mem' MM' B' Rid oResult
    tr r ->
  is_error r ->
  dbCall S TD Ps fs gl lc rm Mem MM (insn_call rid noret tailc rt fv lp) lc' rm' 
    Mem' MM' tr r

| dbCall_external_error1 : forall S TD Ps lc gl fs rid noret tailc fv fid 
                          lp rt la Mem MM oresult Mem' rm,
  LLVMopsem.lookupExFdecViaGV TD Mem Ps gl lc fs fv = 
    Some (fdec_intro (fheader_intro rt fid la)) ->
  LLVMopsem.callExternalFunction Mem fid (params2GVs TD Mem lp lc gl) = 
    (oresult, Mem') ->
  LLVMopsem.exCallUpdateLocals noret rid oresult lc = None ->
  dbCall S TD Ps fs gl lc rm Mem MM (insn_call rid noret tailc rt fv lp) lc rm 
    Mem' MM trace_nil rerror

| dbCall_external_error2 : forall S TD Ps lc gl fs rid noret tailc fv lp rt Mem 
                           MM rm,
  LLVMopsem.lookupExFdecViaGV TD Mem Ps gl lc fs fv = None ->
  dbCall S TD Ps fs gl lc rm Mem MM (insn_call rid noret tailc rt fv lp) lc rm 
    Mem MM trace_nil rerror

with dbSubblock : system -> TargetData -> list product -> GVMap -> GVMap -> 
                  GVMap -> rmetadata -> list mblock -> mem -> mmetadata ->
                  cmds -> 
                  GVMap -> rmetadata -> list mblock -> mem -> mmetadata ->
                  trace -> result -> Prop :=
| dbSubblock_ok : forall S TD Ps lc1 rm1 als1 gl fs Mem1 MM1 cs call0 lc2 rm2 
                  als2 Mem2 MM2 tr1 lc3 rm3 Mem3 MM3 tr2 r,
  dbCmds TD gl lc1 rm1 als1 Mem1 MM1 cs lc2 rm2 als2 Mem2 MM2 tr1 rok ->
  dbCall S TD Ps fs gl lc2 rm2 Mem2 MM2 call0 lc3 rm3 Mem3 MM3 tr2 r ->
  dbSubblock S TD Ps fs gl lc1 rm1 als1 Mem1 MM1 (cs++call0::nil) lc3 rm3 als2 
    Mem3 MM3 (trace_app tr1 tr2) r

| dbSubblock_error : forall S TD Ps lc1 rm1 als1 gl fs Mem1 MM1 cs call0 lc2 rm2 
                     als2 Mem2 MM2 tr1 r,
  dbCmds TD gl lc1 rm1 als1 Mem1 MM1 cs lc2 rm2 als2 Mem2 MM2 tr1 r ->
  is_error r ->
  dbSubblock S TD Ps fs gl lc1 rm1 als1 Mem1 MM1 (cs++call0::nil) lc2 rm2 als2 
    Mem2 MM2 tr1 r

with dbSubblocks : system -> TargetData -> list product -> GVMap -> GVMap -> 
                   GVMap -> rmetadata ->list mblock -> mem -> mmetadata ->
                   cmds -> 
                   GVMap -> rmetadata ->list mblock -> mem -> mmetadata ->
                   trace -> result -> Prop :=
| dbSubblocks_nil : forall S TD Ps lc als gl fs Mem MM rm, 
    dbSubblocks S TD Ps fs gl lc rm als Mem MM nil lc rm als Mem MM trace_nil rok

| dbSubblocks_cons : forall S TD Ps lc1 rm1 als1 gl fs Mem1 MM1 lc2 rm2 als2 Mem2
                     MM2 lc3 als3 rm3 Mem3 MM3 cs cs' t1 t2 r,
    dbSubblock S TD Ps fs gl lc1 rm1 als1 Mem1 MM1 cs lc2 rm2 als2 Mem2 MM2 t1 
      rok ->
    dbSubblocks S TD Ps fs gl lc2 rm2 als2 Mem2 MM2 cs' lc3 rm3 als3 Mem3 MM3 t2
      r ->
    dbSubblocks S TD Ps fs gl lc1 rm1 als1 Mem1 MM1 (cs++cs') lc3 rm3 als3 Mem3 
      MM3 (trace_app t1 t2) r

| dbSubblocks_cons_error : forall S TD Ps lc1 rm1 als1 gl fs Mem1 MM1 lc2 rm2 
                     als2 Mem2 MM2 cs cs' t1 r,
    dbSubblock S TD Ps fs gl lc1 rm1 als1 Mem1 MM1 cs lc2 rm2 als2 Mem2 MM2 t1 r
      ->
    is_error r ->
    dbSubblocks S TD Ps fs gl lc1 rm1 als1 Mem1 MM1 (cs++cs') lc2 rm2 als2 Mem2 
      MM2 t1 r

with dbBlock : system -> TargetData -> list product -> GVMap -> GVMap -> 
               fdef -> State -> State -> trace -> result -> Prop :=
| dbBlock_ok : forall S TD Ps F tr1 tr2 l ps cs cs' tmn gl fs lc1 rm1 als1 
              Mem1 MM1 lc2 rm2 als2 Mem2 MM2 lc3 rm3 als3 Mem3 MM3 lc4 B' tr3,
  dbSubblocks S TD Ps fs gl lc1 rm1 als1 Mem1 MM1 cs lc2 rm2 als2 Mem2 MM2 tr1 
    rok ->
  dbCmds TD gl lc2 rm2 als2 Mem2 MM2 cs' lc3 rm3 als3 Mem3 MM3 tr2 rok ->
  SimpleSE.dbTerminator TD Mem3 F gl (block_intro l ps (cs++cs') tmn) lc3
    tmn B' lc4 tr3 ->
  dbBlock S TD Ps fs gl F
    (mkState (mkEC (block_intro l ps (cs++cs') tmn) lc1 rm1 als1) Mem1 MM1)
    (mkState (mkEC B' lc4 rm3 als3) Mem3 MM3)
    (trace_app (trace_app tr1 tr2) tr3) rok

| dbBlock_error1 : forall S TD Ps F tr1 tr2 l ps cs cs' tmn gl fs lc1 rm1 als1 
                         Mem1 MM1 lc2 rm2 als2 Mem2 MM2 lc3 rm3 als3 Mem3 MM3 r,
  dbSubblocks S TD Ps fs gl lc1 rm1 als1 Mem1 MM1 cs lc2 rm2 als2 Mem2 MM2 tr1 
    rok ->
  dbCmds TD gl lc2 rm2 als2 Mem2 MM2 cs' lc3 rm3 als3 Mem3 MM3 tr2 r ->
  is_error r ->
  dbBlock S TD Ps fs gl F
    (mkState (mkEC (block_intro l ps (cs++cs') tmn) lc1 rm1 als1) Mem1 MM1)
    (mkState (mkEC (block_intro l ps (cs++cs') tmn) lc3 rm3 als3) Mem3 MM2)
    (trace_app tr1 tr2) r

| dbBlock_error2 : forall S TD Ps F tr1 tr2 l ps cs cs' tmn gl fs lc1 rm1 als1 
                         Mem1 MM1 lc2 rm2 als2 Mem2 MM2 r,
  dbSubblocks S TD Ps fs gl lc1 rm1 als1 Mem1 MM1 cs lc2 rm2 als2 Mem2 MM2 tr1 r 
    ->
  is_error r ->
  dbBlock S TD Ps fs gl F
    (mkState (mkEC (block_intro l ps (cs++cs') tmn) lc1 rm1 als1) Mem1 MM1)
    (mkState (mkEC (block_intro l ps (cs++cs') tmn) lc2 rm2 als2) Mem2 MM2)
    (trace_app tr1 tr2) r

with dbBlocks : system -> TargetData -> list product -> GVMap -> GVMap -> 
                fdef -> State -> State -> trace -> result -> Prop :=
| dbBlocks_nil : forall S TD Ps gl fs F state, 
    dbBlocks S TD Ps fs gl F state state trace_nil rok

| dbBlocks_cons : forall S TD Ps gl fs F S1 S2 S3 t1 t2 r,
    dbBlock S TD Ps fs gl F S1 S2 t1 rok ->
    dbBlocks S TD Ps fs gl F S2 S3 t2 r ->
    dbBlocks S TD Ps fs gl F S1 S3 (trace_app t1 t2) r

| dbBlocks_cons_error : forall S TD Ps gl fs F S1 S2 S3 t1 r,
    dbBlock S TD Ps fs gl F S1 S2 t1 r ->
    is_error r ->
    dbBlocks S TD Ps fs gl F S1 S3 t1 r

with dbFdef : value -> typ -> params -> system -> TargetData -> list product -> 
              GVMap -> rmetadata ->GVMap -> GVMap -> 
              mem -> mmetadata -> GVMap -> rmetadata ->list mblock -> 
              mem -> mmetadata ->
              block -> id -> option value -> trace -> result -> Prop :=
| dbFdef_func : forall S TD Ps gl fs fv fid lp lc rm rm0 rid
         l1 ps1 cs1 tmn1 rt la lb Result lc1 rm1 tr1 Mem MM Mem1 MM1 als1
         l2 ps2 cs21 cs22 lc2 rm2 als2 Mem2 MM2 tr2 lc3 rm3 als3 Mem3 MM3 tr3 r,
  LLVMopsem.lookupFdefViaGV TD Mem Ps gl lc fs fv = 
    Some (fdef_intro (fheader_intro rt fid la) lb) ->
  getEntryBlock (fdef_intro (fheader_intro rt fid la) lb) = 
    Some (block_intro l1 ps1 cs1 tmn1) ->
  initRmetadata TD Mem gl la lp rm = Some rm0 ->
  dbBlocks S TD Ps fs gl (fdef_intro (fheader_intro rt fid la) lb) 
    (mkState (mkEC (block_intro l1 ps1 cs1 tmn1) 
      (initLocals la (params2GVs TD Mem lp lc gl)) rm0 nil) Mem MM)
    (mkState (mkEC (block_intro l2 ps2 (cs21++cs22) (insn_return rid rt Result))
      lc1 rm1 als1) Mem1 MM1)
    tr1 rok ->
  dbSubblocks S TD Ps fs gl lc1 rm1 als1 Mem1 MM1 cs21 lc2 rm2 als2 Mem2 MM2 tr2
    rok ->
  dbCmds TD gl lc2 rm2 als2 Mem2 MM2 cs22 lc3 rm3 als3 Mem3 MM3 tr3 r ->
  dbFdef fv rt lp S TD Ps lc rm gl fs Mem MM lc3 rm3 als3 Mem3 MM3
    (block_intro l2 ps2 (cs21++cs22) (insn_return rid rt Result)) rid 
    (Some Result) (trace_app (trace_app tr1 tr2) tr3) r

| dbFdef_func_error1 : forall S TD Ps gl fs fv fid lp lc rm rm0 rid
                l1 ps1 cs1 tmn1 rt la lb Result lc1 rm1 tr1 Mem MM Mem1 MM1 als1
                l2 ps2 cs21 cs22 lc2 rm2 als2 Mem2 MM2 tr2 r,
  LLVMopsem.lookupFdefViaGV TD Mem Ps gl lc fs fv = 
    Some (fdef_intro (fheader_intro rt fid la) lb) ->
  getEntryBlock (fdef_intro (fheader_intro rt fid la) lb) = 
    Some (block_intro l1 ps1 cs1 tmn1) ->
  initRmetadata TD Mem gl la lp rm = Some rm0 ->
  dbBlocks S TD Ps fs gl (fdef_intro (fheader_intro rt fid la) lb) 
    (mkState (mkEC (block_intro l1 ps1 cs1 tmn1) 
      (initLocals la (params2GVs TD Mem lp lc gl)) rm0 nil) Mem MM)
    (mkState (mkEC (block_intro l2 ps2 (cs21++cs22) (insn_return rid rt Result))
      lc1 rm1 als1) Mem1 MM1)
    tr1 rok ->
  dbSubblocks S TD Ps fs gl lc1 rm1 als1 Mem1 MM1 cs21 lc2 rm2 als2 Mem2 MM2 tr2
    r ->
  is_error r ->
  dbFdef fv rt lp S TD Ps lc rm gl fs Mem MM lc2 rm2 als2 Mem2 MM2
    (block_intro l2 ps2 (cs21++cs22) (insn_return rid rt Result)) rid 
    (Some Result) (trace_app tr1 tr2) r

| dbFdef_func_error2 : forall S TD Ps gl fs fv fid lp lc rm rm0 rid
                l1 ps1 cs1 tmn1 rt la lb Result lc1 rm1 tr1 Mem MM Mem1 MM1 als1
                l2 ps2 cs21 cs22 r,
  LLVMopsem.lookupFdefViaGV TD Mem Ps gl lc fs fv = 
    Some (fdef_intro (fheader_intro rt fid la) lb) ->
  getEntryBlock (fdef_intro (fheader_intro rt fid la) lb) = 
    Some (block_intro l1 ps1 cs1 tmn1) ->
  initRmetadata TD Mem gl la lp rm = Some rm0 ->
  dbBlocks S TD Ps fs gl (fdef_intro (fheader_intro rt fid la) lb) 
    (mkState (mkEC (block_intro l1 ps1 cs1 tmn1) 
      (initLocals la (params2GVs TD Mem lp lc gl)) rm0 nil) Mem MM)
    (mkState (mkEC (block_intro l2 ps2 (cs21++cs22) (insn_return rid rt Result))
      lc1 rm1 als1) Mem1 MM1)
    tr1 r ->
  is_error r ->
  dbFdef fv rt lp S TD Ps lc rm gl fs Mem MM lc1 rm1 als1 Mem1 MM1
    (block_intro l2 ps2 (cs21++cs22) (insn_return rid rt Result)) rid 
    (Some Result) tr1 r

| dbFdef_func_error3 : forall S TD Ps gl fs fv fid lp lc rm rid
                l1 ps1 cs1 tmn1 rt la lb Mem MM,
  LLVMopsem.lookupFdefViaGV TD Mem Ps gl lc fs fv = 
    Some (fdef_intro (fheader_intro rt fid la) lb) ->
  getEntryBlock (fdef_intro (fheader_intro rt fid la) lb) = 
    Some (block_intro l1 ps1 cs1 tmn1) ->
  initRmetadata TD Mem gl la lp rm = None ->
  dbFdef fv rt lp S TD Ps lc rm gl fs Mem MM lc rm nil Mem MM
    (block_intro l1 ps1 cs1 tmn1) rid None trace_nil rerror

| dbFdef_func_error4 : forall S TD Ps gl fs fv fid lp lc rm rid B rt la lb Mem 
                       MM,
  LLVMopsem.lookupFdefViaGV TD Mem Ps gl lc fs fv = 
    Some (fdef_intro (fheader_intro rt fid la) lb) ->
  getEntryBlock (fdef_intro (fheader_intro rt fid la) lb) = None ->
  dbFdef fv rt lp S TD Ps lc rm gl fs Mem MM lc rm nil Mem MM B rid None 
    trace_nil rerror

| dbFdef_func_error5 : forall S TD Ps gl fs fv lp lc rm rid B rt Mem MM,
  LLVMopsem.lookupFdefViaGV TD Mem Ps gl lc fs fv = None ->
  dbFdef fv rt lp S TD Ps lc rm gl fs Mem MM lc rm nil Mem MM B rid None 
    trace_nil rerror

| dbFdef_proc : forall S TD Ps gl fs fv fid lp lc rm rm0 rid
          l1 ps1 cs1 tmn1 rt la lb lc1 rm1 tr1 Mem MM Mem1 MM1 als1
          l2 ps2 cs21 cs22 lc2 rm2 als2 Mem2 MM2 tr2 lc3 rm3 als3 Mem3 MM3 tr3 r,
  LLVMopsem.lookupFdefViaGV TD Mem Ps gl lc fs fv = 
    Some (fdef_intro (fheader_intro rt fid la) lb) ->
  getEntryBlock (fdef_intro (fheader_intro rt fid la) lb) = 
    Some (block_intro l1 ps1 cs1 tmn1) ->
  initRmetadata TD Mem gl la lp rm = Some rm0 ->
  dbBlocks S TD Ps fs gl (fdef_intro (fheader_intro rt fid la) lb) 
    (mkState (mkEC (block_intro l1 ps1 cs1 tmn1) 
      (initLocals la (params2GVs TD Mem lp lc gl)) rm0 nil) Mem MM)
    (mkState (mkEC (block_intro l2 ps2 (cs21++cs22) (insn_return_void rid)) lc1 
      rm1 als1) Mem1 MM1)
    tr1 rok ->
  dbSubblocks S TD Ps fs gl lc1 rm1 als1 Mem1 MM1 cs21 lc2 rm2 als2 Mem2 MM2 tr2 
    rok ->
  dbCmds TD gl lc2 rm2 als2 Mem2 MM2 cs22 lc3 rm3 als3 Mem3 MM3 tr3 r ->
  dbFdef fv rt lp S TD Ps lc rm gl fs Mem MM lc3 rm3 als3 Mem3 MM3 
    (block_intro l2 ps2 (cs21++cs22) (insn_return_void rid)) rid None 
    (trace_app (trace_app tr1 tr2) tr3) r

| dbFdef_proc_error1 : forall S TD Ps gl fs fv fid lp lc rm rm0 rid
                 l1 ps1 cs1 tmn1 rt la lb lc1 rm1 tr1 Mem MM Mem1 MM1 als1
                 l2 ps2 cs21 cs22 lc2 rm2 als2 Mem2 MM2 tr2 r,
  LLVMopsem.lookupFdefViaGV TD Mem Ps gl lc fs fv = 
    Some (fdef_intro (fheader_intro rt fid la) lb) ->
  getEntryBlock (fdef_intro (fheader_intro rt fid la) lb) = 
    Some (block_intro l1 ps1 cs1 tmn1) ->
  initRmetadata TD Mem gl la lp rm = Some rm0 ->
  dbBlocks S TD Ps fs gl (fdef_intro (fheader_intro rt fid la) lb) 
    (mkState (mkEC (block_intro l1 ps1 cs1 tmn1) 
      (initLocals la (params2GVs TD Mem lp lc gl)) rm0 nil) Mem MM)
    (mkState (mkEC (block_intro l2 ps2 (cs21++cs22) (insn_return_void rid)) lc1 
      rm1 als1) Mem1 MM1)
    tr1 rok ->
  dbSubblocks S TD Ps fs gl lc1 rm1 als1 Mem1 MM1 cs21 lc2 rm2 als2 Mem2 MM2 tr2
    r ->
  is_error r ->
  dbFdef fv rt lp S TD Ps lc rm gl fs Mem MM lc2 rm2 als2 Mem2 MM2
    (block_intro l2 ps2 (cs21++cs22) (insn_return_void rid)) rid None 
    (trace_app tr1 tr2) r

| dbFdef_proc_error2 : forall S TD Ps gl fs fv fid lp lc rm rm0 rid
                 l1 ps1 cs1 tmn1 rt la lb lc1 rm1 tr1 Mem MM Mem1 MM1 als1
                 l2 ps2 cs21 cs22 r,
  LLVMopsem.lookupFdefViaGV TD Mem Ps gl lc fs fv = 
    Some (fdef_intro (fheader_intro rt fid la) lb) ->
  getEntryBlock (fdef_intro (fheader_intro rt fid la) lb) = 
    Some (block_intro l1 ps1 cs1 tmn1) ->
  initRmetadata TD Mem gl la lp rm = Some rm0 ->
  dbBlocks S TD Ps fs gl (fdef_intro (fheader_intro rt fid la) lb) 
    (mkState (mkEC (block_intro l1 ps1 cs1 tmn1) 
      (initLocals la (params2GVs TD Mem lp lc gl)) rm0 nil) Mem MM)
    (mkState (mkEC (block_intro l2 ps2 (cs21++cs22) (insn_return_void rid)) lc1 
      rm1 als1) Mem1 MM1)
    tr1 r ->
  is_error r ->
  dbFdef fv rt lp S TD Ps lc rm gl fs Mem MM lc1 rm1 als1 Mem1 MM1
    (block_intro l2 ps2 (cs21++cs22) (insn_return_void rid)) rid None 
    tr1 r

| dbFdef_proc_error3 : forall S TD Ps gl fs fv fid lp lc rm rid rt la lb Mem MM
                              l1 ps1 cs1 tmn1,
  LLVMopsem.lookupFdefViaGV TD Mem Ps gl lc fs fv = 
    Some (fdef_intro (fheader_intro rt fid la) lb) ->
  getEntryBlock (fdef_intro (fheader_intro rt fid la) lb) = 
    Some (block_intro l1 ps1 cs1 tmn1) ->
  initRmetadata TD Mem gl la lp rm = None ->
  dbFdef fv rt lp S TD Ps lc rm gl fs Mem MM lc rm nil Mem MM
    (block_intro l1 ps1 cs1 tmn1) rid None trace_nil rerror

| dbFdef_proc_error4 : forall S TD Ps gl fs fv fid lp lc rm rid rt la lb Mem MM 
                              B,
  LLVMopsem.lookupFdefViaGV TD Mem Ps gl lc fs fv = 
    Some (fdef_intro (fheader_intro rt fid la) lb) ->
  getEntryBlock (fdef_intro (fheader_intro rt fid la) lb) = None ->
  dbFdef fv rt lp S TD Ps lc rm gl fs Mem MM lc rm nil Mem MM
    B rid None trace_nil rerror

| dbFdef_proc_error5 : forall S TD Ps gl fs fv lp lc rm Mem MM rid rt B,
  LLVMopsem.lookupFdefViaGV TD Mem Ps gl lc fs fv = None ->
  dbFdef fv rt lp S TD Ps lc rm gl fs Mem MM lc rm nil Mem MM B rid None 
    trace_nil rerror
.

Scheme dbCall_ind3 := Induction for dbCall Sort Prop
  with dbSubblock_ind3 := Induction for dbSubblock Sort Prop
  with dbSubblocks_ind3 := Induction for dbSubblocks Sort Prop
  with dbBlock_ind3 := Induction for dbBlock Sort Prop
  with dbBlocks_ind3 := Induction for dbBlocks Sort Prop
  with dbFdef_ind3 := Induction for dbFdef Sort Prop.

Combined Scheme sb_db_mutind from dbCall_ind3, dbSubblock_ind3,
  dbSubblocks_ind3, dbBlock_ind3, dbBlocks_ind3, dbFdef_ind3.

Hint Constructors dbCall dbSubblock dbSubblocks dbBlock dbBlocks dbFdef.

End SoftBound.

Tactic Notation "sb_dbCmd_cases" tactic(first) tactic(c) :=
  first;
  [ c "dbBop" | c "dbBop_error" | c "dbFBop" | c "dbFBop_eror" |
    c "dbExtractValue" | c "dbExtractValue_error" | 
    c "dbInsertValue" | c "dbInsertValue_error" |
    c "dbMalloc" | c "dbMalloc_error" | c "dbFree" | c "dbFree_error" |
    c "dbAlloca" | c "dbAlloca_error" | 
    c "dbLoad_nptr" | c "dbLoad_ptr" | c "dbLoad_error1" | 
    c "dbLoad_error2" | c "dbLoad_error3" | c "dbLoad_abort" |
    c "dbStore_nptr" | c "dbStore_ptr" | c "dbStore_error1" |
    c "dbStore_error2" | c "dbStore_error3" | c "dbStore_abort" |  
    c "dbGEP" | c "dbGEP_error" |
    c "dbTrunc" | c "dbTrunc_error" |
    c "dbExt" | c "dbExt_error" |
    c "dbBitcast_nptr" | c "dbBitcast_ptr" | c "dbInttoptr" | c "dbOtherCast" |
    c "dbCast_error" | 
    c "dbIcmp" | c "dbIcmp_error" |
    c "dbFcmp" | c "dbFcmp_error" | 
    c "dbSelect_nptr" | c "dbSelect_ptr"| c "dbSelect_error" |
    c "dbLib" | c "dbLib_error" ].

Tactic Notation "sb_dbTerminator_cases" tactic(first) tactic(c) :=
  first;
  [ c "dbBranch" | c "dbBranch_uncond" ].

Tactic Notation "sb_dbCmds_cases" tactic(first) tactic(c) :=
  first;
  [ c "dbCmds_nil" | c "dbCmds_cons" | c "dbCmds_cons_error" ].

Tactic Notation "sb_db_mutind_cases" tactic(first) tactic(c) :=
  first;
  [ c "dbCall_internal" | c "dbCall_external" |
    c "dbCall_internal_error1" | c "dbCall_internal_error2" |
    c "dbCall_external_error1" | c "dbCall_external_error2" |
    c "dbSubblock_ok" | c "dbSubblock_error" | 
    c "dbSubblocks_nil" | c "dbSubblocks_cons" | c "dbSubblocks_cons_error" |
    c "dbBlock_ok" | c "dbBlock_error1" | c "dbBlock_error2" | 
    c "dbBlocks_nil" | c "dbBlocks_cons" | c "dbBlocks_cons_error" | 
    c "dbFdef_func" | c "dbFdef_func_error1" | c "dbFdef_func_error2" |
    c "dbFdef_func_error3" | c "dbFdef_func_error4" | c "dbFdef_func_error5" |
    c "dbFdef_proc" | c "dbFdef_proc_error1" | c "dbFdef_proc_error2" |
    c "dbFdef_proc_error3" | c "dbFdef_proc_error4" | c "dbFdef_proc_error5"
  ].

(*****************************)
(*
*** Local Variables: ***
*** coq-prog-name: "coqtop" ***
*** coq-prog-args: ("-emacs-U" "-I" "~/SVN/sol/vol/src/ssa/monads" "-I" "~/SVN/sol/vol/src/ssa/ott" "-I" "~/SVN/sol/vol/src/ssa/compcert" "-I" "~/SVN/sol/theory/metatheory_8.3" "-I" "~/SVN/sol/vol/src/TV") ***
*** End: ***
 *)
