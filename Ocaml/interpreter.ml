open Printf
open Instructions


type cell = P of prim | I of int32

type vm = {
    ds : int32 list ;
    rs : int32 list ;
    heap : prim array ;
    ip : int ;
}

let cell_of_prim ins = P ins

let prog_to_vm prog = {
    ds = [] ;
    rs = [] ;
    ip = 0 ;
    heap = Array.of_list prog ; }
;;

let stack_prim f vm = match vm.ds with
| [] -> failwith "balls"
| _  -> { vm with ds = f vm.ds }
;;

let dup (x::xs) = x :: x :: xs
let nip (x::y::xs) = x :: xs
let add st = match st with
    | n1 :: n2 :: st' -> Int32.add n1 n2 :: st'
    | _ -> failwith "Stack underflow"
;;

(* primtives *)

let prim_nop vm = vm
let prim_lit n vm = { vm with ds = n :: vm.ds }
let prim_dup = stack_prim dup
let prim_nip = stack_prim nip
let prim_add = stack_prim add



let compile i = match i with
    | Lit n -> prim_lit n
(*    | Str s -> 
    | Call n -> 
    | Jump n -> 
    | Ret -> 
    | Imm p -> *)
    | Dup -> prim_dup
    | Nip -> prim_nip
(*    | Not -> prim_not
    | Eq  -> prim_eq
    | Lt  -> prim_lt
    | Inc -> prim_inc
    | Dec -> prim_dec *)
    | Add -> prim_add
(*    | Sub -> prim_sub
    | Def -> prim_def *)
    | Comment c -> prim_nop
    | i -> failwith ( "Not implemented: " ^ string_of_prim i )
;;



let eval prog =
    let cprog = List.map compile prog in
    let vm = prog_to_vm [] in
    List.map Int32.to_string vm.ds
;;
