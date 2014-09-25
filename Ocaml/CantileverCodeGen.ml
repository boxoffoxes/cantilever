open Printf
open Instructions

let rec compile_instr ins = match ins with
    | Lit n -> sprintf "%ld" n
    | Dup   -> "dup"
    | Nip   -> "nip"
    | Inc   -> "1+"
    | Dec   -> "1-"
    | Add   -> "+"
    | Sub   -> "-"
    | Not   -> "not"
    | Comment s -> match String.contains s '\n' with
                    | true -> sprintf "( %s )" s
                    | false -> sprintf "-- %s" s
;;
let compile prog = List.map compile_instr prog ;;

