open Printf
open Instructions

let id = ref 0 ;;
let dict = Hashtbl.create 32 ;;
(*let called_prims = Hashtbl.create 32 ;;*)

let next_id () =
    let i = !id in
    id := i+1;
    sprintf "%03d" i
;;

let label_for ins = match ins with
    | Str s  ->
            let id = next_id () in
            sprintf "string_%s" id
    | Def "main" ->
            Hashtbl.add dict "main" "cantilever_main" ;
            "cantilever_main"
    | Def w  ->
            let id = sprintf "cantilever_%s" (next_id ()) in
            Hashtbl.add dict w id ;
            id
    | Call w -> Hashtbl.find dict w
    | Lit _  -> failwith "Can't label a literal value!"
    | _      -> "cantilever_prim_" ^ string_of_prim ins
;;


let string_asm ins = match ins with 
| Str s ->
    let lab = label_for ins in
    [ sprintf "movl $%s, %%eax
.data
%s:
    .asciz \"%s\"
10001:
.text
" lab lab s ]
| _ -> failwith (string_of_prim ins ^ " is not a string!")
;;

let indent code = "\t" ^ String.concat "\n\t" code ^ "\n" ;;

let rec logical_prim setcc =
    "test (%esi), %eax"
    :: (setcc ^ " %al")
    :: "and $0xff, %eax"
    :: "dec %eax"
    :: inline_prim Nip
and inline_prim ins = match ins with
    | Lit n  -> inline_prim Dup @ begin match n with
                | 0l    -> [ "xor %eax, %eax" ]
                | (-1l) -> [ "xor %eax, %eax" ; "dec %eax" ]
                | 1l    -> [ "xor %eax, %eax" ; "inc %eax" ]
                | _     -> [ sprintf "movl $%ld, %%eax" n  ]
    end
    | Str s  -> inline_prim Dup @ string_asm ins
    | Dup    -> ["lea -4(%esi), %esi" ; "movl %eax, (%esi)"]
    | Nip    -> ["lea 4(%esi), %esi"]

    | Inc    -> ["inc %eax"]
    | Dec    -> ["dec %eax"]
    | Add    -> "addl (%esi), %eax" :: inline_prim Nip
    | Sub    -> "subl (%esi), %eax" :: inline_prim Nip

    | Not    -> ["not %eax"]

    (* Note: logical prims use the inverse setcc instruction because
     * we use -1 and 0 as true and false *)
    | Eq     -> logical_prim "setne"
    | Ne     -> logical_prim "seteq"
    | Lt     -> logical_prim "setge"
    | Gt     -> logical_prim "setle"
    | LtE    -> logical_prim "setgt"
    | GtE    -> logical_prim "setlt"

    | Call s -> [ sprintf "call %s // %s" (label_for ins) s ]
    | Ret    -> ["ret"]

    | i      -> failwith ("No assembly for " ^ string_of_prim i )
;;

let rec compile_instr ?(inline=false) ins = match ins with
    | Def w  -> sprintf "%s: // %s " (label_for ins) w
    | Comment str ->
            sprintf "/* %s */" str (* TODO: fails if comment contains */ *)
    | _      -> indent (inline_prim ins)
;;

let rec optimise ?(src=[]) prog = match prog with
    (* tail-call elimination *)
    | Call w as ins :: Ret :: prog'  ->
            let asm = sprintf "jmp %s // tail %s" (label_for ins) w in
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
    | Lit n :: Sub :: prog' ->
            let i = sprintf "   subl $%ld, %%eax" n in
            optimise ~src:(i::src) prog'

    (* no optimisation *)
    | i :: prog' ->
            (* no optimisation *)
            let i = compile_instr i in
            optimise ~src:(i::src) prog'
    | [] -> List.rev src
;;

let preamble = []
(* let postamble = [
    ".globl cantilever_init" ;
    "cantilever_init:" ;
    "   pusha" ;
    "   movl %esp, c_stack" ;
    "   movl cantilever_ds_ptr, %esi" ;
    "   movl cantilever_rs_ptr, %esp" ;
    "   call cantilever_main" ;
    "   lea -4(%esi), %esi ; movl %eax, (%esi)" ;
    "   movl %esi, cantilever_ds_ptr" ;
    "   movl c_stack, %esp" ;
    "   popa" ;
    "   ret" ;
    ".data" ;
    "c_stack:" ;
    "   .int 0" ;
] *)
let compile opt prog =
    let compile = match opt with
    | false -> List.map compile_instr
    | true -> optimise ~src:[]
    in
    let asm = compile prog in
    (*List.concat [ preamble ; List.map compile_instr prog]  ; postamble]*)
    try
        ignore ( Hashtbl.find dict "main" ) ;
        asm
    with
    | Not_found ->
        failwith "No 'main' function defined in source program"
    (*List.concat [ preamble ; optimise prog ; postamble]*)
    | _ -> failwith "Arse"
;;
