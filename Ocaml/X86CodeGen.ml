open Printf
open Instructions

let rec compile_instr ins = match ins with
    | Lit n  -> compile_instr Dup ^ " ; " ^ ( match n with
                | 0l    -> "xor %eax, %eax"
                | (-1l) -> "xor %eax, %eax ; dec %eax"
                | 1l    -> "xor %eax, %eax ; inc %eax"
                | _     -> sprintf "movl $%ld, %%eax" n )
    | Dup    -> "   lea -4(%esi), %esi ; movl %eax, (%esi)"
    | Nip    -> "   lea 4(%esi), %esi"

    | Inc    -> "   inc %eax"
    | Dec    -> "   dec %eax"
    | Add    -> "   addl (%esi), %eax ; " ^ compile_instr Nip
    | Sub    -> "   subl (%esi), %eax ; " ^ compile_instr Nip

    | Not    -> "   not %eax"

    | Comment str ->
            sprintf "/* %s */" str (* TODO: fails if comment contains */ *)
;;


let preamble = [
    ".globl cantilever_main" ;
    "cantilever_main:" ;
]
let postamble = ["ret"]
let compile prog =
    List.concat [ preamble ; List.map compile_instr prog ; postamble]
;;
