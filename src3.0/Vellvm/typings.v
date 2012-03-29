(**

   typings.v

   Wrapper around the typing rules generated by Ott in
   typing_rules.ott. Defines relevant tactics and induction principles
   for typing rules.

*)

Require Import Arith.
Require Import Bool.
Require Import List.

Require Import Metatheory.
Require Import syntax.
Require Import infrastructure.
Require Import ListSet.
Require Import List.
Require Import analysis.
Require Import targetdata.
Require Import alist.
Require Import typing_rules.

Module LLVMtypings.

Import LLVMsyntax.
Import LLVMinfra.
Export LLVMtyping_rules.


Tactic Notation "wfconst_cases" tactic(first) tactic(c) :=
  first;
  [ c "wfconst_zero" | c "wfconst_int" | c "wfconst_floatingpoint" |
    c "wfconst_undef" | c "wfconst_null" | c "wfconst_array" |
    c "wfconst_struct" | c "wfconst_gid" | c "wfconst_trunc_int" |
    c "wfconst_trunc_fp" | c "wfconst_zext" | c "wfconst_sext" |
    c "wfconst_fpext" | c "wfconst_ptrtoint" | c "wfconst_inttoptr" |
    c "wfconst_bitcast" | c "wfconst_gep" | c "wfconst_select" |
    c "wfconst_icmp" | c "wfconst_fcmp" | c "wfconst_extractvalue" |
    c "wfconst_insertvalue" | c "wfconst_bop" | c "wfconst_fbop" |
    c "wfconst_nil" | c "wfconst_cons" ].

Scheme wf_const_ind2 := Minimality for wf_const Sort Prop
  with wf_const_list_ind2 := Minimality for wf_const_list Sort Prop.

Combined Scheme wf_const_mutind from wf_const_ind2, wf_const_list_ind2.

Tactic Notation "wfstyp_cases" tactic(first) tactic(c) :=
  first;
  [ c "wf_styp_int" | c "wf_styp_float" | c "wf_styp_double" |
    c "wf_styp_function" | c "wf_styp_structure" | c "wf_styp_array" |
    c "wf_styp_pointer" | c "wf_styp_namedt" | c "wf_styp_nil" |
    c  "wf_styp_cons" ].

Scheme wf_styp_ind2 := Minimality for wf_styp Sort Prop
  with wf_styp_list_ind2 := Minimality for wf_styp_list Sort Prop.

Combined Scheme wf_styp_mutind from wf_styp_ind2, wf_styp_list_ind2.

End LLVMtypings.




