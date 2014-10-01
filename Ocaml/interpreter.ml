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

let prim_add st = match st with
    | n1 :: n2 :: st' -> Int32.add n1 n2 :: st'
    | _ -> failwith "Stack underflow"
;;

let exec vm ins = match ins with
    | Def   -> vm (* TODO *)
    | Lit n -> { vm with ds = n :: vm.ds }
    | Inc -> { vm with ds = prim_add (1l :: vm.ds) }
    | i -> failwith ("Instruction not implemented: " ^ string_of_prim i)
;;

let rec evaluate vm =
    if vm.ip < Array.length vm.heap then evaluate' vm else vm
and evaluate' vm = match vm.heap.(vm.ip) with
    | Imm ins -> evaluate ( exec { vm with ip = vm.ip + 1 } ins )
    | _       -> evaluate { vm with ip = vm.ip + 1 }
;;

let show v =
    sprintf "%ld" v
;;

let eval prog =
    let vm = evaluate ( prog_to_vm prog ) in
    List.map show vm.ds
;;
