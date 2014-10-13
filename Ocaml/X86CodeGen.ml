open Printf
open Instructions

let id = ref 0 ;;
let dict = Hashtbl.create 32 ;;

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

let fun_asm w =
    let i = !id in
    id := i + 1 ;
    Hashtbl.add dict w i ;
    sprintf "cantilever_%03d:  /* %s */" i w
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

    | Def s  -> fun_asm s
    | Call s -> sprintf "   call cantilever_%03d // %s" (Hashtbl.find dict s) s
    | Ret    -> "ret"
    | Comment str ->
            sprintf "/* %s */" str (* TODO: fails if comment contains */ *)
    | i      -> failwith ("No code generator for " ^ string_of_prim i )
;;

let rec optimise ?(src=[]) prog = match prog with
    (* tail-call elimination *)
    | Call s :: Ret :: prog'  ->
            let asm = sprintf "   jmp cantilever_%03d // %s"  (Hashtbl.find dict s) s in
            optimise ~src:(asm::src) prog'

    (* constant propagation *)
    | Lit a :: Lit b :: Add :: prog' ->
            optimise ~src:src (Lit (Int32.add a b) :: prog')
    | Lit a :: Lit b :: Sub :: prog' ->
            optimise ~src:src (Lit (Int32.sub a b) :: prog')

    (* Arithmetic with literals *)
    | Lit 0l :: Add :: prog' ->
            optimise ~src:src prog'
    | Lit 1l :: Add :: prog'  ->
            optimise ~src:(compile_instr Inc::src) prog'
    | Lit n  :: Add :: prog'  ->
            let i = sprintf "   addl $%ld, %%eax" n in
            optimise ~src:(i::src) prog'

    (* no optimisation *)
    | i :: prog' ->
            (* no optimisation *)
            let i = compile_instr i in
            optimise ~src:(i::src) prog'
    | [] -> List.rev src
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
    (*List.concat [ preamble ; optimise prog ; postamble]*)
;;
