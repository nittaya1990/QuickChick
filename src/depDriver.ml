open Pp
open Libnames
open Util
open Constrexpr
open GenericLib
open GenLib
open ArbitrarySizedST
open GenSizedSTMonotonic
open GenSizedSTSizeMonotonic
open Error
open Unify
open SizedProofs
open GenSTCorrect

(** Derivable classes *)
type derivable =
    ArbitrarySizedSuchThat
  | GenSizedSuchThatMonotonicOpt
  | GenSizedSuchThatSizeMonotonicOpt
  | GenSizedSuchThatCorrect
  | SizedProofEqs

let print_der = function
  | ArbitrarySizedSuchThat -> "GenSizedSuchThat"
  | GenSizedSuchThatMonotonicOpt -> "SizeMonotonicOpt"
  | SizedProofEqs -> "SizedProofEqs"
  | GenSizedSuchThatSizeMonotonicOpt -> "SizedMonotonicOpt"
  | GenSizedSuchThatCorrect -> "SizedSuchThatCorrect"


let class_name cn =
  match cn with
  | ArbitrarySizedSuchThat -> "GenSizedSuchThat"
  | GenSizedSuchThatMonotonicOpt -> "SizeMonotonicOpt"
  | SizedProofEqs -> "SizedProofEqs"
  | GenSizedSuchThatSizeMonotonicOpt -> "SizedMonotonicOpt"
  | GenSizedSuchThatCorrect -> "SizedSuchThatCorrect"

(** Name of the instance to be generated *)
let mk_instance_name der tn =
  let prefix = match der with
    | ArbitrarySizedSuchThat -> "GenSizedSuchThat"
    | GenSizedSuchThatMonotonicOpt -> "SizeMonotonicOpt"
    | SizedProofEqs -> "SizedProofEqs"
    | GenSizedSuchThatCorrect -> "SizedSuchThatCorrect"
    | GenSizedSuchThatSizeMonotonicOpt -> "SizedMonotonicOpt"
  in var_to_string (fresh_name (prefix ^ tn))

(** Generic derivation function *)
let deriveDependent (cn : derivable) (c : constr_expr) (n : int) (instance_name : string) =

  let (ty_ctr, ty_params, ctrs, dep_type) : (ty_ctr * (ty_param list) * (dep_ctr list) * dep_type) =
    match coerce_reference_to_dep_dt c with
    | Some dt -> msg_debug (str (dep_dt_to_string dt) ++ fnl()); dt 
    | None -> failwith "Not supported type" in

  msg_debug (str (string_of_int n) ++ fnl ());
  debug_coq_expr (gType ty_params dep_type);

  let (input_types : dep_type list) =
    let rec aux acc i = function
      | DArrow (dt1, dt2) 
      | DProd ((_,dt1), dt2) ->
        if i == n then (* i == n means this is what we generate for - ignore *) 
          aux acc (i+1) dt2
        else (* otherwise this needs to be an input argument *)
          aux (dt1 :: acc) (i+1) dt2
      | DTyParam tp -> acc
      | DTyCtr (c,dts) -> acc
      | DTyVar _ -> acc
    in List.rev (aux [] 1 dep_type) (* 1 because of using 1-indexed counting for the arguments *)       
  in

  let ctr_name = 
    match c with 
    | { CAst.v = CRef (r,_) } -> string_of_reference r
  in

  (* type constructor *)
  let coqTyCtr = gTyCtr ty_ctr in
  (* parameters of the type constructor *)
  let coqTyParams = List.map gTyParam ty_params in

  (* Fully applied type constructor *)
  let full_dt = gApp ~explicit:true coqTyCtr coqTyParams in

  (* Name for type indices *)
  let input_names = List.mapi (fun i _ -> Printf.sprintf "input%d_" i) input_types in
  
  let forGen = "_forGen" in


  let params = List.map (fun tp -> gArg ~assumName:(gTyParam tp) ()) ty_params in
  
  let inputs =
    List.map (fun (n,t) -> gArg ~assumName:(gVar (fresh_name n)) ~assumType:(gType ty_params t) ())
      (List.combine input_names input_types)
  in
  
  (* TODO: These should be generated through some writer monad *)
  (* XXX Put dec_needed in ArbitrarySizedSuchThat *)
  let gen_needed = [] in
  let dec_needed = [] in

  let self_dec = [] in 
  (*     (* Maybe somethign about type paramters here *)
     if !need_dec then [gArg ~assumType:(gApp (gInject (Printf.sprintf "DepDec%n" (dep_type_len dep_type))) [gTyCtr ty_ctr]) 
                            ~assumGeneralized:true ()] 
     else [] in*)

  let arbitraries = ref ArbSet.empty in

  (* this is passed as an arg to arbitrarySizedST. Yikes! *)
  let register_arbitrary dt =
    arbitraries := ArbSet.add dt !arbitraries
  in

  (* The type we are generating for -- not the predicate! *)
  let full_gtyp = (gType ty_params (nthType n dep_type)) in

  (* The type of the dependent generator *)
  let gen_type = gGen (gOption full_gtyp) in

  (* Fully applied predicate (parameters and constructors) *)
  let full_pred inputs =
    gFun [forGen] (fun [fg] -> gApp (full_dt) (list_insert_nth (gVar fg) inputs (n-1)))
  in

  (* The dependent generator  *)
  let gen =
    arbitrarySizedST
      ty_ctr ty_params ctrs dep_type input_names inputs n register_arbitrary
  in

  (* Generate arbitrary parameters *)
  let arb_needed = 
    let rec extract_params = function
      | DTyParam tp -> ArbSet.singleton (DTyParam tp)
      | DTyVar _ -> ArbSet.empty
      | DTyCtr (_, dts) -> List.fold_left (fun acc dt -> ArbSet.union acc (extract_params dt)) ArbSet.empty dts
      | _ -> failwith "Unhandled / arb_needed"  in
    let tps = ArbSet.fold (fun dt acc -> ArbSet.union acc (extract_params dt)) !arbitraries ArbSet.empty in
    ArbSet.fold
      (fun dt acc ->
        (gArg ~assumType:(gApp (gInject "Arbitrary") [gType ty_params dt]) ~assumGeneralized:true ()) :: acc
      ) tps []
  in

  (* Generate typeclass constraints. For each type parameter "A" we need `{_ : <Class Name> A} *)
  let instance_arguments = match cn with
    | ArbitrarySizedSuchThat ->
      params
      @ gen_needed
      @ dec_needed
      @ self_dec
      @ arb_needed
      @ inputs
    | GenSizedSuchThatMonotonicOpt -> params 
    | SizedProofEqs -> params @ inputs
    | GenSizedSuchThatCorrect -> params @ inputs
    | GenSizedSuchThatSizeMonotonicOpt -> params @ inputs
  in

  let rec list_take_drop n l = 
    if n <= 0 then ([], l)
    else match l with 
         | [] -> ([], [])
         | h::t -> let (take,drop) = list_take_drop (n-1) t in (h::take, drop) 
  in 
  
  (* The instance type *)
  let instance_type iargs = match cn with
    | ArbitrarySizedSuchThat ->
      gApp (gInject (class_name cn))
        [gType ty_params (nthType n dep_type);
         full_pred (List.map (fun n -> gVar (fresh_name n)) input_names)]
    | GenSizedSuchThatMonotonicOpt ->
      gProdWithArgs
        ((gArg ~assumType:(gInject "nat") ~assumName:(gInject "size") ()) :: inputs)
        (fun (size :: inputs) ->
(*         let (params, inputs) = list_take_drop (List.length params) paramsandinputs in *)
           gApp (gInject (class_name cn))
                (*              ((List.map gVar params) @  *)
                ([gApp ~explicit:true (gInject "arbitrarySizeST")
                  [full_gtyp; full_pred (List.map gVar inputs); hole; gVar size]]))
    | SizedProofEqs -> gApp (gInject (class_name cn)) [full_pred (List.map (fun n -> gVar (fresh_name n)) input_names)]
    | GenSizedSuchThatCorrect ->
      let pred = full_pred (List.map (fun n -> gVar (fresh_name n)) input_names) in
      gApp (gInject (class_name cn))
        [ pred 
        ; gApp ~explicit:true (gInject "arbitrarySizeST") [hole; pred; hole]]
    | GenSizedSuchThatSizeMonotonicOpt ->
      let pred = full_pred (List.map (fun n -> gVar (fresh_name n)) input_names) in
      gApp (gInject (class_name cn))
        [gApp ~explicit:true (gInject "arbitrarySizeST") [hole; pred; hole]]
  in

  let instance_record iargs =
    match cn with
    | ArbitrarySizedSuchThat -> gen
    | GenSizedSuchThatMonotonicOpt ->
      msg_debug (str "mon type");
      debug_coq_expr (instance_type []);
      genSizedSTMon_body (class_name cn) ty_ctr ty_params ctrs dep_type input_names inputs n register_arbitrary
    | SizedProofEqs ->
      sizedEqProofs_body (class_name cn) ty_ctr ty_params ctrs dep_type input_names inputs n register_arbitrary
    | GenSizedSuchThatCorrect ->
      let moninst = (class_name GenSizedSuchThatMonotonicOpt) ^ ctr_name in
      let ginst = (class_name ArbitrarySizedSuchThat) ^ ctr_name in
      let setinst = (class_name SizedProofEqs) ^ ctr_name in
      genSizedSTCorr_body (class_name cn) ty_ctr ty_params ctrs dep_type input_names inputs n register_arbitrary
        (gInject moninst) (gInject ginst) (gInject setinst)
    | GenSizedSuchThatSizeMonotonicOpt ->
      genSizedSTSMon_body (class_name cn) ty_ctr ty_params ctrs dep_type input_names inputs n register_arbitrary

  in

  msg_debug (str "Instance Type: " ++ fnl ());
  debug_coq_expr (instance_type [gInject "input0"; gInject "input1"]);

  declare_class_instance instance_arguments instance_name instance_type instance_record
;;

(*
VERNAC COMMAND EXTEND DeriveArbitrarySizedSuchThat
  | ["DeriveArbitrarySizedSuchThat" constr(c) "for" constr(n) "as" string(s1)] -> [deriveDependent ArbitrarySizedSuchThat c n s1]
END;;
  *)
