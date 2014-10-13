open Printf
open Instructions

let rec compile_instr ins = match ins with
    | Lit n -> sprintf "%ld" n
    | Str s -> "s>" ^ s
    | Dup   -> "dup"
    | Nip   -> "nip"
    | Inc   -> "1+"
    | Dec   -> "1-"
    | Add   -> "+"
    | Sub   -> "-"
    | Eq    -> "="
    | Lt    -> "<"
    | Not   -> "not"
    | Def s -> s ^ ":"
    | Call s -> s
    | Tail s -> s ^ " ;"
    | Ret   -> ";"
    | Comment s -> begin
        match String.contains s '\n' with
                    | true -> sprintf "( %s )" s
                    | false -> sprintf "-- %s" s
    end
    | i     -> failwith ("Could not compile: " ^ string_of_prim i)
;;
let compile prog = List.map compile_instr prog ;;

