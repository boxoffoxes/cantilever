open Printf
open Instructions

let id = ref 0 ;;

let string_asm str = let i = !id in 
    id := !id + 1 ;
    sprintf "movl $string_%03d, %%eax
.data
string_%03d:
    .asciz \"%s\"
10001:
.text
" i i str
;;


let rec compile_instr ins = match ins with
    | Lit n  -> compile_instr Dup ^ " ; " ^ ( match n with
                | 0l    -> "xor %eax, %eax"
                | (-1l) -> "xor %eax, %eax ; dec %eax"
                | 1l    -> "xor %eax, %eax ; inc %eax"
                | _     -> sprintf "movl $%ld, %%eax" n )
    | Str s  -> compile_instr Dup ^ " ; " ^ string_asm s
    | Dup    -> "   lea -4(%esi), %esi ; movl %eax, (%esi)"
    | Nip    -> "   lea 4(%esi), %esi"

    | Inc    -> "   inc %eax"
    | Dec    -> "   dec %eax"
    | Add    -> "   addl (%esi), %eax ; " ^ compile_instr Nip
    | Sub    -> "   subl (%esi), %eax ; " ^ compile_instr Nip

    | Not    -> "   not %eax"

    | Eq     -> "   test (%esi), %eax ; setne %al ; and $0xff, %eax ; dec %eax ; " ^ compile_instr Nip
    | Lt     -> "   cmpl (%esi), %eax ; setge %al ; and $0xff, %eax ; dec %eax ; " ^ compile_instr Nip

    | Comment str ->
            sprintf "/* %s */" str (* TODO: fails if comment contains */ *)
;;


let preamble = [
    ".globl cantilever_main" ;
    "cantilever_main:" ;
    "   pusha" ;
    "   movl %esp, c_stack" ;
    "   movl cantilever_ds_ptr, %esi" ;
    "   movl cantilever_rs_ptr, %esp" ;
]
let postamble = [
    "   lea -4(%esi), %esi ; movl %eax, (%esi)" ;
    "   movl %esi, cantilever_ds_ptr" ;
    "   movl c_stack, %esp" ;
    "   popa" ;
    "   ret" ;
    ".data" ;
    "c_stack:" ;
    "   .int 0" ;
]
let compile prog =
    List.concat [ preamble ; List.map compile_instr prog ; postamble]
;;
