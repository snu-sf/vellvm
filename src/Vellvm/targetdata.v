Require Import Zpower.
Require Import Zdiv.
Require Import List.
Require Import Metatheory.
Require Import syntax.
Require Import Coqlib.
Require Import alist.
Require Import vellvm_tactics.

(*Require Import Coqlib_old.*)

(* This file defines data layouts. *)

Module LLVMtd.

Export LLVMsyntax.

(**
 Alignments come in two flavors: ABI and preferred. ABI alignment (abi_align,
 below) dictates how a type will be aligned within an aggregate and when used
 as an argument.  Preferred alignment (pref_align, below) determines a type's
 alignment when emitted as a global.

 Specifier string details:

 E|e: Endianness. "E" specifies a big-endian target data model, "e"
 specifies a little-endian target data model.

 p:size:abi_align:pref_align: Pointer size, ABI and preferred alignment.

 Type:size:abi_align:pref_align: Numeric type alignment. Type is one of i|f|v|a,
 corresponding to integer, floating point, or aggregate.  Size indicates the
 size, e.g., 32 or 64 bits.

 Note that in the case of aggregates, 0 is the default ABI and preferred
 alignment. This is a special case, where the aggregate's computed worst-case
 alignment will be used.

 At any case, if 0 is the preferred alignment, then the preferred alignment
 equals to its ABI alignment.

  // Default alignments
  align_type,      abi_align, pref_align, bit_width
  INTEGER_ALIGN,   1,         1,          1   // i1
  INTEGER_ALIGN,   1,         1,          8   // i8
  INTEGER_ALIGN,   2,         2,          16  // i16
  INTEGER_ALIGN,   4,         4,          32  // i32
  INTEGER_ALIGN,   4,         8,          64  // i64
  FLOAT_ALIGN,     4,         4,          32  // f32
  FLOAT_ALIGN,     8,         8,          64  // f64
  AGGREGATE_ALIGN, 0,         8,          0   // struct
  PTR,             8,         8,          32  // ptr
  BigEndian

 When LLVM is determining the alignment for a given type, it uses the following
 rules:
   1. If the type sought is an exact match for one of the specifications, that
      specification is used.
   2. If no match is found, and the type sought is an integer type, then the
      smallest integer type that is larger than the bitwidth of the sought type
      is used. If none of the specifications are larger than the bitwidth then
      the the largest integer type is used. For example, given the default
      specifications above, the i7 type will use the alignment of i8 (next
      largest) while both i65 and i256 will use the alignment of i64 (largest
      specified).
*)

Definition TargetData := (layouts * namedts)%type.

Definition DTD :=  (layout_be::
                    layout_int Size.One Align.One Align.One::
                    layout_int Size.Eight Align.One Align.One::
                    layout_int Size.Sixteen Align.Two Align.Two::
                    layout_int Size.ThirtyTwo Align.Four Align.Four::
                    layout_int Size.SixtyFour Align.Four Align.Four::
                    layout_float Size.ThirtyTwo Align.Four Align.Four::
                    layout_float Size.SixtyFour Align.Four Align.Four::
                    layout_aggr Size.Zero Align.Zero Align.Eight::
                    layout_ptr Size.ThirtyTwo Align.Four Align.Four::nil).

(** RoundUpAlignment - Round the specified value up to the next alignment
    boundary specified by Alignment.  For example, 7 rounded up to an
    alignment boundary of 4 is 8.  8 rounded up to the alignment boundary of 4
    is 8 because it is already aligned. *)
Definition RoundUpAlignment (val alignment:nat) : nat :=
  let zv := Z_of_nat val in
  let za := Z_of_nat alignment in
  let zr := zv + za in
  nat_of_Z (zr / za * za).

(** getAlignmentInfo - Return the alignment (either ABI if ABIInfo = true or
    preferred if ABIInfo = false) the target wants for the specified datatype.
*)
Fixpoint _getIntAlignmentInfo (los:layouts) (BitWidth: nat) (ABIInfo: bool)
  (obest:option (nat*(nat*nat))) (olargest:option (nat*(nat*nat))) {struct los}
    : option nat :=
  match los with
  | nil =>
    (* Okay, we didn't find an exact solution.  Fall back here depending on what
       is being looked for.

       If we didn't find an integer alignment, fall back on most conservative. *)
    match (obest, olargest) with
    | (Some (_, (babi, bpre)), _) =>
      (if ABIInfo then Some babi else Some bpre)
    | (None, Some (_, (labi, lpre))) =>
      (if ABIInfo then Some labi else Some lpre)
    | _ => None
    end
  | (layout_int isz abi pre)::los' =>
    if beq_nat (Size.to_nat isz) BitWidth
    then
      (* Check to see if we have an exact match and remember the best match we
         see. *)
      (if ABIInfo then Some (Align.to_nat abi) else Some (Align.to_nat pre))
    else
      (* The obest match so far depends on what we're looking for.
         The "obest match" for integers is the smallest size that is larger than
         the BitWidth requested.

         However, if there isn't one that's larger, then we must use the
         largest one we have (see below) *)
      match (obest, olargest, le_lt_dec BitWidth (Size.to_nat isz)) with
      | (Some (bestbt, _), Some (largestbt, _), left _ (* BitWidth <= isz *) ) =>
        match (le_lt_dec largestbt (Size.to_nat isz)) with
        | left _ (* isz <= largestbt *) =>
          _getIntAlignmentInfo los' BitWidth ABIInfo obest olargest
        | right _ (* largestbt < isz *) =>
          _getIntAlignmentInfo los' BitWidth ABIInfo
            (Some (Size.to_nat isz, (Align.to_nat abi, Align.to_nat pre)))
            (Some (Size.to_nat isz, (Align.to_nat abi, Align.to_nat pre)))
        end

      | (Some (bestbt, _), Some (largestbt, _), right _ (* isz < BitWidth *) ) =>
        match (le_lt_dec largestbt (Size.to_nat isz)) with
        | left _ (* isz <= largestbt *) =>
          match (le_lt_dec (Size.to_nat isz) bestbt) with
          | left _ (* bestbt <= isz *) =>
            _getIntAlignmentInfo los' BitWidth ABIInfo obest olargest
          | right _ (* isz < bestbt *) =>
            _getIntAlignmentInfo los' BitWidth ABIInfo
            (Some (Size.to_nat isz, (Align.to_nat abi, Align.to_nat pre)))
            (Some (Size.to_nat isz, (Align.to_nat abi, Align.to_nat pre)))
          end
        | right _ (* largestbt < isz *) =>
          _getIntAlignmentInfo los' BitWidth ABIInfo
            (Some (Size.to_nat isz, (Align.to_nat abi, Align.to_nat pre)))
            (Some (Size.to_nat isz, (Align.to_nat abi, Align.to_nat pre)))
        end

      | (None, Some (largestbt, _), left _ (* BitWidth <= isz *) ) =>
        match (le_lt_dec largestbt (Size.to_nat isz)) with
        | left _ (* isz <= largestbt *) =>
          _getIntAlignmentInfo los' BitWidth ABIInfo obest olargest
        | right _ (* largestbt < isz *) =>
          _getIntAlignmentInfo los' BitWidth ABIInfo obest
            (Some (Size.to_nat isz, (Align.to_nat abi, Align.to_nat pre)))
        end

      | (None, Some (largestbt, _), right _ (* isz < BitWidth *) ) =>
        match (le_lt_dec largestbt (Size.to_nat isz)) with
        | left _ (* isz <= largestbt *) =>
          _getIntAlignmentInfo los' BitWidth ABIInfo
            (Some (Size.to_nat isz, (Align.to_nat abi, Align.to_nat pre)))
            olargest
        | right _ (* largestbt < isz *) =>
          _getIntAlignmentInfo los' BitWidth ABIInfo
            (Some (Size.to_nat isz, (Align.to_nat abi, Align.to_nat pre)))
            (Some (Size.to_nat isz, (Align.to_nat abi, Align.to_nat pre)))
        end

      | (Some (bestbt, _), None, left _ (* BitWidth <= isz *) ) =>
          _getIntAlignmentInfo los' BitWidth ABIInfo obest
            (Some (Size.to_nat isz, (Align.to_nat abi, Align.to_nat pre)))
      | (Some (bestbt, _), None, right _ (* isz < BitWidth *) ) =>
          match (le_lt_dec (Size.to_nat isz) bestbt) with
          | left _ (* bestbt <= isz *) =>
            _getIntAlignmentInfo los' BitWidth ABIInfo obest
            (Some (Size.to_nat isz, (Align.to_nat abi, Align.to_nat pre)))
          | right _ (* isz < bestbt *) =>
            _getIntAlignmentInfo los' BitWidth ABIInfo
            (Some (Size.to_nat isz, (Align.to_nat abi, Align.to_nat pre)))
            (Some (Size.to_nat isz, (Align.to_nat abi, Align.to_nat pre)))
          end
      | (None, None, left _ (* BitWidth <= isz *) ) =>
          _getIntAlignmentInfo los' BitWidth ABIInfo obest
            (Some (Size.to_nat isz, (Align.to_nat abi, Align.to_nat pre)))
      | (None, None, right _ (* isz < BitWidth *) ) =>
          _getIntAlignmentInfo los' BitWidth ABIInfo
            (Some (Size.to_nat isz, (Align.to_nat abi, Align.to_nat pre)))
            (Some (Size.to_nat isz, (Align.to_nat abi, Align.to_nat pre)))
      end
  | _::los' =>
    _getIntAlignmentInfo los' BitWidth ABIInfo obest olargest
  end.

Definition getIntDefaultAlignmentInfo (BitWidth: nat) (ABIInfo: bool) : nat :=
  match (le_lt_dec 1 BitWidth) with
  | left _ (* BitWidth <= 1 *) => if BitWidth then 1%nat else 1%nat
  | right _ (* 1 < BitWidth *) =>
    match (le_lt_dec 8 BitWidth) with
    | left _ (* BitWidth <= 8 *) => if BitWidth then 1%nat else 1%nat
    | right _ (* 8 < BitWidth *) =>
      match (le_lt_dec 16 BitWidth) with
      | left _ (* BitWidth <= 16 *) => if BitWidth then 2%nat else 2%nat
      | right _ (* 16 < BitWidth *) =>
        match (le_lt_dec 32 BitWidth) with
        | left _ (* BitWidth <= 32 *) => if BitWidth then 4%nat else 4%nat
        | right _ (* 32 < BitWidth *) => if BitWidth then 4%nat else 8%nat
        end
      end
    end
  end.

Definition getIntAlignmentInfo (los:layouts) (BitWidth: nat) (ABIInfo: bool)
  : nat :=
  match (_getIntAlignmentInfo los BitWidth ABIInfo None None) with
  | Some n => n
  | None => getIntDefaultAlignmentInfo BitWidth ABIInfo
  end.

(** Target pointer alignment when ABIInfo is true
    Return target's alignment for stack-based pointers when ABIInfo is false *)
Fixpoint _getPointerAlignmentInfo (los:layouts) (ABIInfo: bool) : option nat :=
  match los with
  | nil => None
  | (layout_ptr psz abi pre)::_ =>
      if ABIInfo then Some (Align.to_nat abi) else Some (Align.to_nat pre)
  | _::los' => _getPointerAlignmentInfo los' ABIInfo
  end.

Definition getPointerAlignmentInfo (los:layouts) (ABIInfo: bool) : nat :=
  match (_getPointerAlignmentInfo los ABIInfo) with
  | Some n => n
  | None => 8%nat
  end.

Fixpoint _getStructAlignmentInfo (los:layouts) (ABIInfo: bool) : option nat :=
  match los with
  | nil => None
  | (layout_aggr sz abi pre)::_ =>
      if ABIInfo then Some (Align.to_nat abi) else Some (Align.to_nat pre)
  | _::los' => _getStructAlignmentInfo los' ABIInfo
  end.

Definition getStructAlignmentInfo (los:layouts) (ABIInfo: bool) : nat :=
  match (_getStructAlignmentInfo los ABIInfo) with
  | Some n => n
  | None => if ABIInfo then 0%nat else 8%nat
  end.

(** Target pointer size *)
Fixpoint _getPointerSize (los:layouts) : option sz :=
  match los with
  | nil => None
  | (layout_ptr psz abi pre)::_ =>
      Some (nat_of_Z (ZRdiv (Z_of_nat psz) 8))
  | _::los' => _getPointerSize los'
  end.

Definition getPointerSize0 (los:layouts) : sz := Size.Four.
(* FIXME: ptr size is always 4-byte for the POPL submission
  match (_getPointerSize los) with
  | Some n => n
  | None => Size.Four
  end.
*)

Definition getPointerSize (TD:TargetData) : sz :=
  let '(td, _) := TD in
  getPointerSize0 td.

(** Target pointer size, in bits *)
Definition getPointerSizeInBits (los:layouts) : sz :=
  Size.mul Size.Eight (getPointerSize0 los).

Fixpoint getFloatAlignmentInfo (los:layouts)  (BitWidth: nat) (ABIInfo: bool)
    : nat :=
  match los with
  | nil =>
    if beq_nat BitWidth 32
    then 4%nat
    else
      if beq_nat BitWidth 64
      then 8%nat
      else getIntAlignmentInfo los BitWidth ABIInfo
  | (layout_float isz abi pre)::los' =>
    if beq_nat (Size.to_nat isz) BitWidth
    then
      Align.to_nat (if ABIInfo then abi else pre)
    else
      getFloatAlignmentInfo los' BitWidth ABIInfo
  | _::los' => getFloatAlignmentInfo los' BitWidth ABIInfo
  end.

(** Merged getTypeSizeInBits, getTypeStoreSize, getTypeAllocSize,
    getTypeAllocSizeInBits, getAlignment and getStructLayout

    This internal version needs a mapping from named types to their
    TypeSizeInBits and Alignment.

    getTypeSizeInBits_and_Alignment uses the result calculated by
      getTypeSizeInBits_and_Alignment_for_namedts
*)

(* Since Coq doesn't allow mutual recursion with nested inductives, we
   have to do a small hack to use nested fixpoints and bind both
   functions to a toplevel name *)

Definition _getListTypeSizeInBits_and_Alignment_aux
  (_getTypeSizeInBits_and_Alignment :
    layouts -> list (id * (nat * nat)) -> bool -> typ -> option (nat * nat)) :=
fix _getListTypeSizeInBits_and_Alignment
  (los:layouts) (nts:list (id*(nat*nat)))
  (lt:list typ) {struct lt} : option (nat*nat) :=
  let getTypeStoreSize :=
      fun typeSizeInBits => nat_of_Z (ZRdiv (Z_of_nat typeSizeInBits) 8) in

  let getTypeAllocSize :=
      fun typeSizeInBits ABIalignment =>
      (* Round up to the next alignment boundary *)
      RoundUpAlignment (getTypeStoreSize typeSizeInBits) ABIalignment in

  let getTypeAllocSizeInBits :=
      fun typeSizeInBits ABIalignment =>
      (getTypeAllocSize typeSizeInBits ABIalignment * 8)%nat in

  match lt with
  | nil => Some (0%nat, 0%nat)
  | t :: lt' =>
    (* getting ABI alignment *)
    match (_getListTypeSizeInBits_and_Alignment los nts lt',
           _getTypeSizeInBits_and_Alignment los nts true t) with
    | (Some (struct_sz, struct_al), Some (sub_sz, sub_al)) =>
          (* Add padding if necessary to align the data element properly. *)
          (* Keep track of maximum alignment constraint. *)
          (* Consume space for this data item *)
          Some ((struct_sz + getTypeAllocSizeInBits sub_sz sub_al)%nat,
                 match (le_lt_dec sub_al struct_al) with
                 | left _ (* sub_al <= struct_al *) => struct_al
                 | right _ (* struct_al < sub_al *) => sub_al
                 end)
    | _ => None
    end
  end.

Fixpoint _getTypeSizeInBits_and_Alignment
  (los:layouts) (nts:list (id*(nat*nat)))
  (abi_or_pref:bool) (t:typ) : option (nat*nat) :=
  let getTypeStoreSize :=
      fun typeSizeInBits => nat_of_Z (ZRdiv (Z_of_nat typeSizeInBits) 8) in

  let getTypeAllocSize :=
      fun typeSizeInBits ABIalignment =>
      (* Round up to the next alignment boundary *)
      RoundUpAlignment (getTypeStoreSize typeSizeInBits) ABIalignment in

  let getTypeAllocSizeInBits :=
      fun typeSizeInBits ABIalignment =>
      (getTypeAllocSize typeSizeInBits ABIalignment * 8)%nat in

  match t with
  | typ_label => None
                 (* Some (Size.to_nat (getPointerSizeInBits los),  *)
                 (*       getPointerAlignmentInfo los abi_or_pref)  *)
  | typ_pointer _ => Some (Size.to_nat (getPointerSizeInBits los),
                           getPointerAlignmentInfo los abi_or_pref)

  | typ_void => Some (8%nat, getIntAlignmentInfo los 8%nat abi_or_pref)

  | typ_int sz => Some (Size.to_nat sz, getIntAlignmentInfo los (Size.to_nat sz)
                        abi_or_pref)

  | typ_array n t' =>
    match n with
    | O =>
      (* Empty arrays have alignment of 1 byte. *)
      Some (8%nat, 1%nat)
    | _ =>
      (* getting ABI alignment *)
      match (_getTypeSizeInBits_and_Alignment los nts true t') with
      | None => None
      | Some (sz, al) =>
          Some (((getTypeAllocSizeInBits sz al)*Size.to_nat n)%nat, al)
      end
    end

  | typ_struct lt =>
    (* Loop over each of the elements, placing them in memory. *)
    match (_getListTypeSizeInBits_and_Alignment_aux _getTypeSizeInBits_and_Alignment los nts lt) with
    | None => None
    | (Some (sz, al)) =>
      (* Empty structures have alignment of 1 byte. *)
      (* Add padding to the end of the struct so that it could be put in an array
         and all array elements would be aligned correctly. *)
       match sz with
       | O => Some (8%nat, 1%nat)
       | _ => Some (sz, al)
       end
    end

  | typ_floatpoint fp_float => 
      Some (32%nat, getFloatAlignmentInfo los 32%nat abi_or_pref) 
  | typ_floatpoint fp_double => 
      Some (64%nat, getFloatAlignmentInfo los 64%nat abi_or_pref) 
  | typ_floatpoint fp_x86_fp80 => None
      (* Some (80%nat, getFloatAlignmentInfo los 64%nat abi_or_pref)  *)
  | typ_floatpoint fp_fp128 => None
      (* Some (128%nat, getFloatAlignmentInfo los 128%nat abi_or_pref)  *)
  | typ_floatpoint fp_ppc_fp128 => None
      (* Some (128%nat, getFloatAlignmentInfo los 128%nat abi_or_pref)  *)
  | typ_metadata => None
  | typ_function _ _ _ => None
  | typ_namedt id0 => lookupAL _ nts id0
  end.

Definition _getListTypeSizeInBits_and_Alignment :=
  _getListTypeSizeInBits_and_Alignment_aux _getTypeSizeInBits_and_Alignment.

(* calculate the TypeSizeInBits and Alignment for namedts
   Assumption: nts[i] should only use named types from nts[j] where j > i
   So, getTypeSizeInBits_and_Alignment_for_namedts rev-ed the orignal nts.
   The well-formedness should check such invariant for named types.

   With this invariant, we could have type

   %1 = {%1*}
   %2 = {%1}
   %3 = {%2; %1, %3*}
   %4 = {%5*}
   %5 = {%4*}

   But we cannot have

   %1 = {%2}
   %2 = {%1}
*)
Fixpoint _getTypeSizeInBits_and_Alignment_for_namedts
  (los:layouts) (nts:namedts) (abi_or_pref:bool)  : list (id*(nat*nat)) :=
match nts with
| nil => nil
| (id0, ts0)::nts' =>
  let results := _getTypeSizeInBits_and_Alignment_for_namedts los nts'
                abi_or_pref in
  match _getTypeSizeInBits_and_Alignment los results abi_or_pref 
         (typ_struct ts0) with
  | None => results
  | Some r => (id0, r)::results
  end
end.

Definition getTypeSizeInBits_and_Alignment_for_namedts
  (TD:TargetData) (abi_or_pref:bool)  : list (id*(nat*nat)) :=
let (los, nts) := TD in
_getTypeSizeInBits_and_Alignment_for_namedts los nts abi_or_pref.


Definition getTypeSizeInBits_and_Alignment (TD:TargetData) (abi_or_pref:bool)
  (t:typ) : option (nat*nat) :=
  let '(los, nts) := TD in
  _getTypeSizeInBits_and_Alignment los
    (getTypeSizeInBits_and_Alignment_for_namedts TD abi_or_pref)
    abi_or_pref t.


Definition getListTypeSizeInBits_and_Alignment (TD:TargetData) (abi_or_pref:bool)
  (lt:list typ) : option (nat*nat) :=
  let '(los, nts) := TD in
  _getListTypeSizeInBits_and_Alignment los
    (getTypeSizeInBits_and_Alignment_for_namedts TD abi_or_pref) lt.

(** abi_or_pref Flag that determines which alignment is returned. true
  returns the ABI alignment, false returns the preferred alignment.

  Get the ABI (abi_or_pref == true) or preferred alignment (abi_or_pref
  == false) for the requested type t.
 *)
Definition getAlignment (TD:TargetData) (t:typ) (abi_or_pref:bool) : option nat
  :=
  match (getTypeSizeInBits_and_Alignment TD abi_or_pref t) with
  | (Some (sz, al)) => Some al
  | None => None
  end.

(** getABITypeAlignment - Return the minimum ABI-required alignment for the
    specified type. *)
Definition getABITypeAlignment (TD:TargetData) (t:typ) : option nat :=
  getAlignment TD t true.

(** getPrefTypeAlignment - Return the preferred stack/global alignment for
    the specified type.  This is always at least as good as the ABI alignment. *)
Definition getPrefTypeAlignment (TD:TargetData) (t:typ) : option nat :=
  getAlignment TD t false.

(*
 Size examples:

   Type        SizeInBits  StoreSizeInBits  AllocSizeInBits[*]
   ----        ----------  ---------------  ---------------
    i1            1           8                8
    i8            8           8                8
    i19          19          24               32
    i32          32          32               32
    i100        100         104              128
    i128        128         128              128
    Float        32          32               32
    Double       64          64               64
    X86_FP80     80          80               96

   [*] The alloc size depends on the alignment, and thus on the target.
       These values are for x86-32 linux.
*)

(** getTypeSizeInBits - Return the number of bits necessary to hold the
    specified type.  For example, returns 36 for i36 and 80 for x86_fp80. *)
Definition getTypeSizeInBits (TD:TargetData) (t:typ) : option nat :=
  match (getTypeSizeInBits_and_Alignment TD true t) with
  | (Some (sz, al)) => Some sz
  | None => None
  end.

(** getTypeStoreSize - Return the maximum number of bytes that may be
    overwritten by storing the specified type.  For example, returns 5
    for i36 and 10 for x86_fp80. *)
Definition getTypeStoreSize (TD:TargetData) (t:typ) : option nat :=
  match (getTypeSizeInBits TD t) with
  | None => None
  | Some sz => Some (nat_of_Z (ZRdiv (Z_of_nat sz) 8))
  end.

(** getTypeStoreSizeInBits - Return the maximum number of bits that may be
    overwritten by storing the specified type; always a multiple of 8.  For
    example, returns 40 for i36 and 80 for x86_fp80.*)
Definition getTypeStoreSizeInBits (TD:TargetData) (t:typ) : option nat :=
  match (getTypeStoreSize TD t) with
  | None => None
  | Some n => Some (8*n)%nat
  end.

(** getTypeAllocSize - Return the offset in bytes between successive objects
    of the specified type, including alignment padding.  This is the amount
    that alloca reserves for this type.  For example, returns 12 or 16 for
    x86_fp80, depending on alignment. *)
Definition getTypeAllocSize (TD:TargetData) (t:typ) : option sz :=
  match (getTypeStoreSize TD t, getABITypeAlignment TD t) with
  | (Some ss, Some ta) =>
    (* Round up to the next alignment boundary *)
    Some (RoundUpAlignment ss ta)
  | _ => None
  end.

(** getTypeAllocSizeInBits - Return the offset in bits between successive
    objects of the specified type, including alignment padding; always a
    multiple of 8.  This is the amount that alloca reserves for this type.
    For example, returns 96 or 128 for x86_fp80, depending on alignment. *)
Definition getTypeAllocSizeInBits (TD:TargetData) (t:typ) : option nat :=
  match (getTypeAllocSize TD t) with
  | None => None
  | Some n => Some (8*n)%nat
  end.

Definition getStructSizeInBytes (TD:TargetData) (t:typ) : option nat :=
match t with
| typ_struct lt =>
  match (getTypeSizeInBits TD t) with
  | Some sz => Some (nat_of_Z (ZRdiv (Z_of_nat sz) 8))
  | None => None
  end
| _ => None
end.

Definition getStructSizeInBits (TD:TargetData) (t:typ) : option nat :=
match t with
| typ_struct lt => getTypeSizeInBits TD t
| _ => None
end.

Definition getStructAlignment (TD:TargetData) (t:typ) : option nat :=
match t with
| typ_struct lt => getABITypeAlignment TD t
| _ => None
end.

Fixpoint _getStructElementOffset (TD:TargetData) (ts:list typ) (idx:nat)
         (ofs : nat) : option nat :=
match (ts, idx) with
| (_, O) => Some ofs
| (t :: ts', S idx') =>
    match (getTypeAllocSize TD t, getABITypeAlignment TD t) with
    | (Some sub_sz, Some sub_al) =>
       _getStructElementOffset TD ts' idx' (ofs + RoundUpAlignment sub_sz sub_al)
    | _ => None
    end
| _ => None
end.

Definition getStructElementOffset (TD:TargetData) (t:typ) (idx:nat) : option nat
  :=
match t with
| typ_struct lt => _getStructElementOffset TD lt idx 0
| _ => None
end.

Definition getStructElementOffsetInBits (TD:TargetData) (t:typ) (idx:nat)
  : option nat :=
match t with
| typ_struct lt => match (_getStructElementOffset TD lt idx 0) with
                   | None => None
                   | Some n => Some (n*8)%nat
                   end
| _ => None
end.

(** getElementContainingOffset - Given a valid offset into the structure,
    return the structure index that contains it. *)
Fixpoint _getStructElementContainingOffset (TD:TargetData) (ts:list typ)
  (offset:nat) (idx:nat) (cur : nat) : option nat :=
match ts with
| nil => None
| t :: ts' =>
    match (getTypeAllocSize TD t, getABITypeAlignment TD t) with
    | (Some sub_sz, Some sub_al) =>
         match (le_lt_dec offset (RoundUpAlignment sub_sz sub_al + cur)) with
         | left _ (* (RoundUpAlignment struct_sz sub_al + sub_sz) <= offset*)
             => _getStructElementContainingOffset TD ts' offset (S idx)
                   (RoundUpAlignment sub_sz sub_al + cur)
         | right _ => Some idx
         end
    | _ => None
    end
end.

(**
   Multiple fields can have the same offset if any of them are zero sized.
   For example, in { i32, [0 x i32], i32 }, searching for offset 4 will stop
   at the i32 element, because it is the last element at that offset.  This is
   the right one to return, because anything after it will have a higher
   offset, implying that this element is non-empty.
*)
Definition getStructElementContainingOffset (TD:TargetData) (t:typ) (offset:nat)
  : option nat :=
match t with
| typ_struct lt => _getStructElementContainingOffset TD lt offset 0 0
| _ => None
end.

(* FIXME: abi_or_pref cannot always be true,
   We should use different flag when t types global or aggregate
*)

(* Check if a type has a finite size and a well-formed alignment. *)
Definition feasible_typs_aux_
  (feasible_typ_aux :
    layouts -> list (id * Prop) -> typ -> Prop) :=
fix feasible_typs_aux los nts (lt:list typ) : Prop :=
match lt with
| nil => True
| t :: lt' =>
    feasible_typ_aux los nts t /\ feasible_typs_aux los nts lt'
end.

Fixpoint feasible_typ_aux los (nts:list (id*Prop)) t : Prop :=
match t with
| typ_int sz => 
    (getIntAlignmentInfo los (Size.to_nat sz) true > 0)%nat /\
    (sz > 0)%nat
| typ_pointer _ => (getPointerAlignmentInfo los true > 0)%nat
| typ_floatpoint fp_float => (getFloatAlignmentInfo los 32%nat true > 0)%nat
| typ_floatpoint fp_double => (getFloatAlignmentInfo los 64%nat true > 0)%nat
| typ_array _ t' => feasible_typ_aux los nts t'
| typ_struct ts => feasible_typs_aux_ feasible_typ_aux los nts ts
| typ_namedt nid =>
    match lookupAL _ nts nid with
    | Some re => re
    | _ => False
    end
| _ => False
end.

Definition feasible_typs_aux :=
  feasible_typs_aux_ feasible_typ_aux.

Hint Unfold feasible_typs_aux.

Fixpoint feasible_typ_for_namedts (los:layouts) (nts:namedts)
  : list (id*Prop) :=
match nts with
| nil => nil
| (id0, ts0)::nts' =>
  let results := feasible_typ_for_namedts los nts' in
  (id0, feasible_typ_aux los results (typ_struct ts0))::results
end.

Definition feasible_typ (TD:TargetData) t : Prop :=
let '(los, nts) := TD in
feasible_typ_aux los (feasible_typ_for_namedts los nts) t.

Definition feasible_typs (TD:TargetData) lt : Prop :=
let '(los, nts) := TD in
feasible_typs_aux los (feasible_typ_for_namedts los nts) lt.

(* Properties of feasible_typ *)
Lemma RoundUpAlignment_spec : 
  forall a b, (b > 0)%nat -> (RoundUpAlignment a b >= a)%nat.
Proof.
  intros. unfold RoundUpAlignment.
  assert ((Z_of_nat a + Z_of_nat b) / Z_of_nat b * Z_of_nat b >= Z_of_nat a)%Z
    as J.
    apply Coqlib.roundup_is_correct.
      destruct b; try solve [contradict H; omega | apply Coqlib.Z_of_S_gt_O].
  apply nat_of_Z_inj_ge in J.
  rewrite Coqlib.Z_of_nat_eq in J. auto.
Qed.

Lemma feasible_array_typ_inv : forall TD s t,
  feasible_typ TD (typ_array s t) -> feasible_typ TD t.
Proof.
  intros.
  simpl in *.
  unfold getTypeSizeInBits_and_Alignment in *.
  destruct TD.
  destruct (_getTypeSizeInBits_and_Alignment l0
           (_getTypeSizeInBits_and_Alignment_for_namedts l0 n true)
           true t) as [[]|]; eauto.
Qed.

Lemma feasible_struct_typ_inv : forall TD ts,
  feasible_typ TD (typ_struct ts) -> feasible_typs TD ts.
Proof.
  intros.
  unfold feasible_typ in H.
  unfold feasible_typs.
  unfold getTypeSizeInBits_and_Alignment in *.
  destruct TD.
  simpl in *.
  destruct (_getListTypeSizeInBits_and_Alignment l0
           (_getTypeSizeInBits_and_Alignment_for_namedts l0 n true)
           ts) as [[]|]; eauto.
Qed.

Lemma feasible_cons_typs_inv : forall TD t lt,
  feasible_typs TD (t :: lt) ->
  feasible_typ TD t /\ feasible_typs TD lt.
Proof.
  intros. destruct TD as [los nts].
  simpl in *. auto.
Qed.

Lemma feasible_nil_typs: forall TD, feasible_typs TD nil.
Proof. destruct TD; simpl; auto. Qed.

Lemma feasible_cons_typs: forall TD t lt,
  feasible_typs TD (t :: lt) <->
  feasible_typ TD t /\ feasible_typs TD lt.
Proof. destruct TD; simpl. intros. split; auto. Qed.

Definition feasible_typ_aux_weaken_prop (t:typ) := forall los nm1 nm2,
  uniq (nm2++nm1) ->
  feasible_typ_aux los nm1 t ->
  feasible_typ_aux los (nm2++nm1) t.

Definition feasible_typs_aux_weaken_prop (lt:list typ) :=
  forall los nm1 nm2,
  uniq (nm2++nm1) ->
  feasible_typs_aux los nm1 lt ->
  feasible_typs_aux los (nm2++nm1) lt.

Lemma feasible_typ_aux_weaken_mutrec :
  (forall t, feasible_typ_aux_weaken_prop t) /\
  (forall lt, feasible_typs_aux_weaken_prop lt).
Proof.
  (typ_cases (apply typ_mutind; 
    unfold feasible_typ_aux_weaken_prop, 
           feasible_typs_aux_weaken_prop) Case);
    intros; simpl in *; try solve [eauto | inversion H | inversion H1 ].
Case "typ_struct".
  apply H; trivial.
Case "typ_namedt".
  inv_mbind.
  erewrite lookupAL_weaken; eauto.
Case "typ_cons".
  destruct H2.
  split; eauto.
Qed.

Lemma feasible_typ_aux_weaken: forall t los nm1 nm2,
  uniq (nm2++nm1) ->
  feasible_typ_aux los nm1 t ->
  feasible_typ_aux los (nm2++nm1) t.
Proof.
  destruct feasible_typ_aux_weaken_mutrec as [J _].
  unfold feasible_typ_aux_weaken_prop in J. auto.
Qed.

Lemma feasible_typ_for_namedts_dom: forall los nm,
  dom (feasible_typ_for_namedts los nm) [=] dom nm.
Proof.
  induction nm as [|[]]; simpl; fsetdec.
Qed.

Lemma feasible_typ_for_namedts_uniq: forall los nm
  (Huniq: uniq nm), uniq (feasible_typ_for_namedts los nm).
Proof.
  induction 1; simpl; auto.
    simpl_env.
    constructor; auto.
      assert (J:=@feasible_typ_for_namedts_dom los E).
      fsetdec.
Qed.

Lemma feasible_typ_for_namedts_cons : forall los nm1 nm2,
  exists re,
    feasible_typ_for_namedts los (nm2++nm1) =
      re ++ feasible_typ_for_namedts los nm1.
Proof.
  induction nm2 as [|[]]; simpl.
    exists nil. auto.

    destruct IHnm2 as [re IHnm2].
    rewrite IHnm2.
    simpl_env. eauto.
Qed.

Lemma feasible_typ_aux_weakening: forall los t
  (nm1 nm2:namedts) (Huniq: uniq (nm2++nm1)),
  feasible_typ_aux los (feasible_typ_for_namedts los nm1) t ->
  feasible_typ_aux los (feasible_typ_for_namedts los (nm2++nm1)) t.
Proof.
  intros.  
  destruct (@feasible_typ_for_namedts_cons los nm1 nm2) as [re J].
  rewrite J.
  apply feasible_typ_aux_weaken; auto.
    unfold id in *.
    rewrite <- J.
    eapply feasible_typ_for_namedts_uniq; eauto.
Qed.

Lemma feasible_typ_for_namedts_spec1: forall los nts2 lt2 i0 r nts1 nts
  (Huniq: uniq nts),
  lookupAL _ (feasible_typ_for_namedts los nts) i0 = Some r ->
  nts = nts1 ++ (i0,lt2) :: nts2 ->  
  feasible_typs_aux los (feasible_typ_for_namedts los nts2) lt2 = r.
Proof.
  induction nts1 as [|[]]; intros; subst; simpl in *.
    destruct (i0 == i0); unfold feasible_typs_aux; try congruence; auto.

    inv Huniq.
    simpl_env in H4.
    destruct (i0 == a); subst.
      contradict H4; fsetdec.
      apply IHnts1 in H; auto.
Qed.

Lemma feasible_typ_for_namedts_spec2: forall los i0 r nts2 
  lt2 nts1 nts (Huniq: uniq nts),
  feasible_typs_aux los (feasible_typ_for_namedts los nts2) lt2 = r ->
  nts = nts1 ++ (i0,lt2) :: nts2 ->  
  lookupAL _ (feasible_typ_for_namedts los nts) i0 = Some r.
Proof.
  induction nts1 as [|[]]; intros; subst; simpl in *.
    destruct (@eq_dec atom (EqDec_eq_of_EqDec atom EqDec_atom) i0 i0); 
      try congruence; auto.
     
    inv Huniq.
    simpl_env in H3.
    destruct (@eq_dec atom (EqDec_eq_of_EqDec atom EqDec_atom) i0 i1); subst.
      contradict H3; fsetdec.
      eapply IHnts1 in H1; eauto.
Qed.

Lemma feasible_typ_spec1: forall (los : layouts) (i0 : id)
  (nts : namedts) (lt2 : list typ) r
  (HeqR : Some lt2 = lookupAL (list typ) nts i0) (Huniq: uniq nts)
  (H:lookupAL _ (feasible_typ_for_namedts los nts) i0 = Some r),
  r -> feasible_typs_aux los (feasible_typ_for_namedts los nts) lt2.
Proof.
  intros. 
  assert (exists nts1, exists nts2, nts = nts1 ++ (i0,lt2) :: nts2) as J.
    apply lookupAL_middle_inv; auto.
  destruct J as [nts1 [nts2 J]]; subst.
  eapply feasible_typ_for_namedts_spec1 with (nts1:=nts1) (nts2:=nts2) in H; 
    eauto.
  rewrite_env ((nts1 ++ [(i0, lt2)]) ++ nts2).
  change (feasible_typ_aux los
    (feasible_typ_for_namedts los ((nts1 ++ [(i0, lt2)]) ++ nts2)) 
    (typ_struct lt2)).
  eapply feasible_typ_aux_weakening; simpl_env; eauto.
  simpl. fold feasible_typs_aux. rewrite H. auto.
Qed.

Definition feasible_typ_aux__getTypeSizeInBits_and_Alignment_prop' (t:typ) := 
  forall los nm1 nm2,
  feasible_typ_aux los nm1 t -> 
  (forall (i0 : id) (P : Prop) (HeqR : Some P = lookupAL Prop nm1 i0) (H : P),
   exists sz0 : nat,
     exists al : nat,
       lookupAL (nat * nat) nm2 i0 = Some (sz0, al) /\ 
       (sz0 > 0)%nat /\ (al > 0)%nat) ->
  exists sz, exists al,
    _getTypeSizeInBits_and_Alignment los nm2 true t = Some (sz, al) /\ 
    (sz > 0)%nat /\ (al > 0)%nat.

Definition feasible_typs_aux__getListTypeSizeInBits_and_Alignment_prop'
  (lt:list typ) := forall los nm1 nm2,
  feasible_typs_aux los nm1 lt ->
  (forall (i0 : id) (P : Prop) (HeqR : Some P = lookupAL Prop nm1 i0) (H : P),
   exists sz0 : nat,
     exists al : nat,
       lookupAL (nat * nat) nm2 i0 = Some (sz0, al) /\ 
       (sz0 > 0)%nat /\ (al > 0)%nat) ->
  (forall t, In t lt -> feasible_typ_aux los nm1 t) /\
  exists sz, exists al,
    _getListTypeSizeInBits_and_Alignment los nm2 lt = Some (sz,al) /\
    ((sz > 0)%nat -> (al > 0)%nat).

Lemma feasible_typ_aux__getTypeSizeInBits_and_Alignment_mutrec' :
  (forall t, feasible_typ_aux__getTypeSizeInBits_and_Alignment_prop' t) /\
  (forall lt, feasible_typs_aux__getListTypeSizeInBits_and_Alignment_prop' lt).
Proof.
  (typ_cases (apply typ_mutind;
    unfold feasible_typ_aux__getTypeSizeInBits_and_Alignment_prop', 
           feasible_typs_aux__getListTypeSizeInBits_and_Alignment_prop') Case);
    intros;
    unfold getTypeSizeInBits_and_Alignment in *;
    simpl in *; try (destruct TD);
    try solve [eauto | inversion H | inversion H1 | destruct H; eauto].
Case "typ_floatingpoint".
  destruct f0; try solve [inv H].
    exists 32%nat. exists (getFloatAlignmentInfo los 32 true).
    split; auto. omega.

    exists 64%nat. exists (getFloatAlignmentInfo los 64 true).
    split; auto. omega.
Case "typ_array".
  eapply H in H0; eauto.
  destruct H0 as [sz [al [J1 [J2 J3]]]].
  rewrite J1.
  destruct s.
    exists 8%nat. exists 1%nat. split; auto. omega.

    exists (RoundUpAlignment
               (Coqlib.nat_of_Z (Coqlib.ZRdiv (Z_of_nat sz) 8)) al * 8 *
             Size.to_nat (S s))%nat.
    exists al. split; auto. split; auto.
    assert (RoundUpAlignment (Coqlib.nat_of_Z (Coqlib.ZRdiv (Z_of_nat sz) 8)) al
      >= (Coqlib.nat_of_Z (Coqlib.ZRdiv (Z_of_nat sz) 8)))%nat as J4.
      apply RoundUpAlignment_spec; auto.
    assert (Coqlib.ZRdiv (Z_of_nat sz) 8 > 0) as J5.
      apply Coqlib.ZRdiv_prop3; try omega.
    apply nat_of_Z_inj_gt in J5; try omega.
    simpl in J5.
    assert (RoundUpAlignment (Coqlib.nat_of_Z (Coqlib.ZRdiv (Z_of_nat sz) 8)) al
      * 8 > 0)%nat as J6. omega. clear J4 J5.
    assert (Size.to_nat (S s) > 0)%nat as J7. unfold Size.to_nat. omega.
    remember (RoundUpAlignment (Coqlib.nat_of_Z (Coqlib.ZRdiv (Z_of_nat sz) 8)) 
      al * 8)%nat as R1. 
    remember (Size.to_nat (S s)) as R2. 
    clear - J6 J7.
    assert (0 * R2 < R1 * R2)%nat as J.
      apply mult_lt_compat_r; auto.
    simpl in J. auto.

Case "typ_struct".
  eapply H in H0; eauto.
  destruct H0 as [J0 [sz [al [J1 J2]]]].
  unfold _getListTypeSizeInBits_and_Alignment in J1.
  rewrite J1.
  destruct sz.
    exists 8%nat. exists 1%nat. split; auto. omega.
    exists (S sz0). exists al. split; auto. omega. 

Case "typ_pointer".
  unfold LLVMtd.feasible_typ_aux in H0. simpl in H0.
  unfold getPointerSizeInBits, Size.to_nat.
  simpl.
  exists 32%nat. exists (getPointerAlignmentInfo los true).
  split; auto. omega.

Case "typ_namedt".
  match goal with
  | H: match ?x with
       | Some _ => _
       | None => False
       end |- _ => remember x as R; destruct R as [|]; tinv H; eauto
  end.
  
Case "typ_nil".
  split.
    intros. tauto.
    simpl. exists 0%nat. exists 0%nat. split; auto.

Case "typ_cons".
  destruct H1 as [J1 J2]. 
  eapply H0 in J2; eauto.
  destruct J2 as [J21 [sz2 [al2 [J22 J23]]]].
  split.
    intros. 
    destruct H1 as [H1 | H1]; subst; auto.
      
    simpl.
    unfold getListTypeSizeInBits_and_Alignment in J22.
    unfold getTypeSizeInBits_and_Alignment_for_namedts in J22.
    rewrite J22.
    eapply H in J1; eauto.
    destruct J1 as [sz1 [al1 [J11 [J12 J13]]]].
    unfold getTypeSizeInBits_and_Alignment_for_namedts in J11.
    rewrite J11.
    destruct (le_lt_dec al1 al2); eauto.
      exists (sz2 +
             RoundUpAlignment
               (Coqlib.nat_of_Z (Coqlib.ZRdiv (Z_of_nat sz1) 8)) al1 * 8)%nat.
      exists al2.
      split; auto.
        intros. clear - J13 l1. omega.
Qed.

Lemma feasible_typ_aux__getTypeSizeInBits_and_Alignment : forall t los nm1 nm2,
  feasible_typ_aux los nm1 t -> 
  (forall (i0 : id) (P : Prop) (HeqR : Some P = lookupAL Prop nm1 i0) (H : P),
   exists sz0 : nat,
     exists al : nat,
       lookupAL (nat * nat) nm2 i0 = Some (sz0, al) /\ 
       (sz0 > 0)%nat /\ (al > 0)%nat) ->
  exists sz, exists al,
    _getTypeSizeInBits_and_Alignment los nm2 true t = Some (sz, al) /\ 
    (sz > 0)%nat /\ (al > 0)%nat.
Proof.
  destruct feasible_typ_aux__getTypeSizeInBits_and_Alignment_mutrec'; auto.
Qed.

Lemma feasible_typs_aux__getListTypeSizeInBits_and_Alignment :
  forall (lt:list typ) los nm1 nm2,
  feasible_typs_aux los nm1 lt ->
  (forall (i0 : id) (P : Prop) (HeqR : Some P = lookupAL Prop nm1 i0) (H : P),
   exists sz0 : nat,
     exists al : nat,
       lookupAL (nat * nat) nm2 i0 = Some (sz0, al) /\ 
       (sz0 > 0)%nat /\ (al > 0)%nat) ->
  (forall t, In t lt -> feasible_typ_aux los nm1 t) /\
  exists sz, exists al,
    _getListTypeSizeInBits_and_Alignment los nm2 lt = Some (sz,al) /\
    ((sz > 0)%nat -> (al > 0)%nat).
Proof.
  destruct feasible_typ_aux__getTypeSizeInBits_and_Alignment_mutrec'; auto.
Qed.

Lemma feasible_typ_for_namedts__getTypeSizeInBits_and_Alignment_for_namedts: 
  forall los nts (i0 : id) (P : Prop),
  Some P = lookupAL Prop (feasible_typ_for_namedts los nts) i0 ->
  P ->
  exists sz0 : nat,
    exists al : nat,
      lookupAL (nat * nat)
        (_getTypeSizeInBits_and_Alignment_for_namedts los nts true) i0 =
      Some (sz0, al) /\ (sz0 > 0)%nat /\ (al > 0)%nat.
Proof.
  induction nts as [|[i1 lt1]]; simpl; intros.
    congruence.

    destruct (@eq_dec atom (EqDec_eq_of_EqDec atom EqDec_atom) i0 i1); subst.
      inv H.
      eapply feasible_typs_aux__getListTypeSizeInBits_and_Alignment in H0; eauto.
      destruct H0 as [_ [sz [al [J1 J2]]]].
      unfold _getListTypeSizeInBits_and_Alignment in J1.
      rewrite J1.
      destruct sz as [|sz].
        simpl. 
        destruct (@eq_dec atom (EqDec_eq_of_EqDec atom EqDec_atom) i1 i1); 
          subst; try congruence.
        exists 8%nat. exists 1%nat. split; auto. split; omega.

        simpl. 
        destruct (@eq_dec atom (EqDec_eq_of_EqDec atom EqDec_atom) i1 i1); 
          subst; try congruence.
        exists (S sz). exists al. 
        split; auto. omega.

      apply IHnts with (P:=P) in H; auto.
      destruct H as [sz [al [J1 J2]]].
      match goal with
      | |- exists _, exists _, 
             lookupAL _ (match ?x with
                        | Some _ => _
                        | None => _
                        end) _ = _ /\ _ => destruct x
      end.
        simpl.
        destruct (@eq_dec atom (EqDec_eq_of_EqDec atom EqDec_atom) i0 i1); 
          try congruence. 
        rewrite J1.
        exists sz. exists al. split; auto.

        rewrite J1.
        exists sz. exists al. split; auto.
Qed.

Lemma feasible_typ_inv : forall t TD,
  feasible_typ TD t ->
  exists sz, exists al,
    getTypeSizeInBits_and_Alignment TD true t = Some (sz, al) /\ 
    (sz > 0)%nat /\ (al > 0)%nat.
Proof.
  unfold feasible_typ, getTypeSizeInBits_and_Alignment.
  destruct TD as [los nts].
  intros.
  eapply feasible_typ_aux__getTypeSizeInBits_and_Alignment; eauto.
  unfold getTypeSizeInBits_and_Alignment_for_namedts.
  apply feasible_typ_for_namedts__getTypeSizeInBits_and_Alignment_for_namedts.
Qed.

Lemma feasible_typ_inv' : forall t TD,
  feasible_typ TD t ->
  exists sz, exists al,
    getTypeSizeInBits_and_Alignment TD true t = Some (sz, al) /\ (al > 0)%nat.
Proof.
  intros.
  apply feasible_typ_inv in H.
  destruct H as [sz [al [H1 [H2 H3]]]]; eauto.
Qed.

(* Properties of getTypeAllocSize *)
Lemma getTypeAllocSize_inv : forall TD typ5 sz,
  getTypeAllocSize TD typ5 = Some sz ->
  exists sz0, exists al0, getABITypeAlignment TD typ5 = Some al0 /\
    getTypeSizeInBits_and_Alignment TD true typ5 = Some (sz0, al0) /\
    sz = RoundUpAlignment (Coqlib.nat_of_Z (Coqlib.ZRdiv (Z_of_nat sz0) 8)) al0.
Proof.
  intros.
  unfold getTypeAllocSize in H.
  unfold getTypeStoreSize in H.
  unfold getTypeSizeInBits in H.
  unfold getABITypeAlignment in *.
  unfold getAlignment in *.
  remember (getTypeSizeInBits_and_Alignment TD true typ5) as R.
  destruct R as [[sz1 al1]|]; inv H.
  eauto.
Qed.

Lemma getTypeAllocSize_inv' : forall los nts typ5 sz sz2 al2,
  getTypeAllocSize (los,nts) typ5 = Some sz ->
  _getTypeSizeInBits_and_Alignment los
         (_getTypeSizeInBits_and_Alignment_for_namedts los nts true)
         true typ5 = Some (sz2, al2) ->
  sz = RoundUpAlignment (Coqlib.nat_of_Z (Coqlib.ZRdiv (Z_of_nat sz2) 8)) al2.
Proof.
  intros.
  apply getTypeAllocSize_inv in H.
  destruct H as [sz1 [al1 [J1 [J2 J3]]]].
  unfold getTypeSizeInBits_and_Alignment in J2.
  unfold getTypeSizeInBits_and_Alignment_for_namedts in J2.
  rewrite J2 in H0. inv H0. auto.
Qed.

Lemma getTypeAllocSize_roundup : forall los nts sz2 al2 t
  (H31 : feasible_typ (los, nts) t)
  (J6 : _getTypeSizeInBits_and_Alignment los
         (_getTypeSizeInBits_and_Alignment_for_namedts los nts true)
         true t = Some (sz2, al2))
  (s0 : sz) (HeqR3 : Some s0 = getTypeAllocSize (los, nts) t),
  ((Coqlib.nat_of_Z (Coqlib.ZRdiv (Z_of_nat sz2) 8)) +
    (s0 - (Coqlib.nat_of_Z (Coqlib.ZRdiv (Z_of_nat sz2) 8))))%nat = s0.
Proof.
  intros.
  unfold getTypeAllocSize, getABITypeAlignment, getAlignment, getTypeStoreSize,
    getTypeSizeInBits, getTypeSizeInBits_and_Alignment,
    getTypeSizeInBits_and_Alignment_for_namedts in HeqR3.
  rewrite J6 in HeqR3.
  inv HeqR3.
  assert (RoundUpAlignment (Coqlib.nat_of_Z (Coqlib.ZRdiv (Z_of_nat sz2) 8))
      al2 >= (Coqlib.nat_of_Z (Coqlib.ZRdiv (Z_of_nat sz2) 8)))%nat as J8.
    apply RoundUpAlignment_spec.
      eapply feasible_typ_inv' in H31; eauto.
      destruct H31 as [sz0 [al0 [J13 J14]]].
      unfold getTypeSizeInBits_and_Alignment,
             getTypeSizeInBits_and_Alignment_for_namedts in J13.
      rewrite J6 in J13. inv J13. auto.
  rewrite <- le_plus_minus; auto.
Qed.

(* A layout is well-formed if its alignments are positive. *)
Definition wf_layouts (los:layouts) : Prop :=
forall ABInfo,
  (getPointerAlignmentInfo los ABInfo > 0)%nat /\
forall BitWidth,
  (getIntAlignmentInfo los BitWidth ABInfo > 0)%nat /\
  (getFloatAlignmentInfo los BitWidth ABInfo > 0)%nat.

End LLVMtd.
