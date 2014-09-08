


type prim =
    | Nop
(*    | S | K | I *)
	| Lit of int32 | StrLit of string
    | Def of int | Comment of string | Quote of int
    | Call of int | Tail of int | Jump of int | Ret
    | If of int | Else of int | EndIf of int
    | Fetch | Store
    | Add | Sub | Div | Mul | Mod
    | And | Or | Xor | Not
    | Eq | NEq | Lt | Gt | LtE | GtE
    | Dup | Swap | Nip | Drop
    | EmitInt | Emit
    | End 

type prog = prim list


let translate instr = match instr with
    | Nop      -> "nop"
    | Lit n    -> String.concat "" [ "_dup ; movl $" ; Int32.to_string n ; ", %eax" ]
    | Def i    -> String.concat "" [ "word_" ; string_of_int i ; ":" ]
    | Comment _ -> ""
    | Quote i  -> String.concat "" [ "$word_" ; string_of_int i ] 
    | Call i   -> String.concat "" [ "call word_" ; string_of_int i ]
    | Tail i | Jump i
               -> String.concat "" [ "jmp word_" ; string_of_int i ]
    | EndIf i  -> String.concat "" [ string_of_int i ; ":" ]
    | Ret      -> "ret"
    | Add      -> "addl (%ebp), %eax ; _nip"
    | Sub      -> "subl (%ebp), %eax ; _nip"
    | And      -> "and (%ebp), %eax ; _nip"
    | Or       -> "or  (%ebp), %eax ; _nip"
    | And      -> "xor (%ebp), %eax ; _nip"
    | Not      -> "not %eax"
    | Dup      -> "_dup"
    | Swap     -> "_swap"
    | Nip      -> "_nip"
    | Drop     -> "_drop"
    | EmitInt  -> "call prim_emit_int"
    | Emit     -> "call prim_emit"
;;

let compile_conditional ins cid = 
    let asm = match ins with
        | Eq  -> "cmp (%ebp), %eax ; _drop ; _drop ; jne "  (* if they're equal then don't jump! *)
        | NEq -> "cmp (%ebp), %eax ; _drop ; _drop ; je "
        | Lt  -> "cmp (%ebp), %eax ; _drop ; _drop ; jge "
        | Gt  -> "cmp (%ebp), %eax ; _drop ; _drop ; jle "
        | LtE -> "cmp (%ebp), %eax ; _drop ; _drop ; jg "
        | GtE -> "cmp (%ebp), %eax ; _drop ; _drop ; jl "
        | other   -> String.concat "" [ translate other ; "\ntest %eax, %eax ; _drop ; jz " ]
    in 
    String.concat "" [ asm ; string_of_int cid ; "f" ]
;;


let rec compile ?(asm=[]) prog = match prog with
    | [] -> List.rev asm
    | ins :: If i :: prog' -> compile ~asm:(compile_conditional ins i :: asm) prog'
    | ins :: prog' -> compile ~asm:(translate ins :: asm) prog'
;;


let reverse_lookup instr = match instr with
    | Nop      -> "Nop"
	| Lit n    -> Printf.sprintf "Lit %ld" n
    | StrLit s -> Printf.sprintf "StrLit «%s»" s
    | Def i    -> Printf.sprintf "Def %x" i 
    | Comment s -> Printf.sprintf "Comment «%s»" s
    | Quote i  -> Printf.sprintf "Quote %x" i
    | Call i   -> Printf.sprintf "Call %x" i
    | Tail i   -> Printf.sprintf "Tail %x" i
    | Jump i   -> Printf.sprintf "Jump %d" i
    | Ret      -> "Ret"
    | If i     -> Printf.sprintf "If %d" i
    | Else i   -> Printf.sprintf "Else %d" i
    | EndIf i  -> Printf.sprintf "EndIf %d" i
    | Fetch    -> "Fetch" 
    | Store    -> "Store"
    | Add      -> "Add" 
    | Sub      -> "Sub" 
    | Div      -> "Div" 
    | Mul      -> "Mul" 
    | Mod      -> "Mod"
    | And      -> "And" 
    | Or       -> "Or" 
    | Xor      -> "Xor" 
    | Not      -> "Not"
    | Eq       -> "Eq" 
    | NEq      -> "NEq" 
    | Lt       -> "Lt" 
    | Gt       -> "Gt" 
    | LtE      -> "LtE" 
    | GtE      -> "GtE"
    | Dup      -> "Dup" 
    | Swap     -> "Swap" 
    | Nip      -> "Nip" 
    | Drop     -> "Drop"
    | EmitInt  -> "EmitInt" 
    | Emit     -> "Emit"
    | End      -> "End" 
;;

let show_ins i =  Printf.printf "%s   " (reverse_lookup i) ;;
(*let dump prog = List.iter show_ins prog ; print_newline () ;;*)
let dump prog = print_endline ( String.concat "\n" ( compile prog ) ) ;;



type word =
    | Prim of prim
    | Fun of prog

let consume_to pred st = 
    let buf = Buffer.create 16 in
    while not ( pred (Stream.peek st) ) do
            Buffer.add_char buf (Stream.next st) ;
    done ;
    Buffer.contents buf
;;


let intrinsic p prog _   = p :: prog ;;
let branch prog str      = Nop :: prog ;;
let begin_cond prog str  = If 0 :: prog ;;
let end_cond prog str    = EndIf 0 :: prog ;;
let call_return prog str = match prog with
    | Call f :: prog' -> Tail f :: prog'
    | prog            -> Ret :: prog
;;
let quote prog str       = Nop :: prog ;;

let comment term prog st = 
    let com = consume_to ((=) (Some term) ) st in
    Stream.junk st ; (* discard the terminating character *)
    ( Comment com ) :: prog
;;
let string_lit term prog st = 
    Stream.junk st ; (* discard the first space *)
    let str = consume_to ((=) (Some term) ) st in
    Stream.junk st ; (* discard the terminating character *)
    ( StrLit str ) :: prog
;;
let lit word prog stream =
    let n = Int32.of_string word in
    (Lit n) :: prog
;;


let is_whitespace c     = compare (Some ' ') c  >= 0 ;;
let is_not_whitespace c = compare (Some ' ') c  <  0 ;;


let next_word st = 
    ignore ( consume_to is_not_whitespace st ) ;
    consume_to is_whitespace st
;;

let dictionary = Hashtbl.create 255 ;;

let rec define prog st =
    let w = next_word st in
    let id = Hashtbl.length dictionary in
    Hashtbl.add dictionary w (intrinsic (Call id)) ; (* add to dictionary *)
    (Def id) :: prog
;;

let prims = [
    "s\""   , string_lit '"' ;
    "s:"    , string_lit '\n' ;

    ":"     , define ;
    "'"     , quote ;
    "--"    , comment '\n' ;
    "("     , comment ')' ;

    ";"     , call_return ;

    "?["    , begin_cond ;
    "]["    , branch ;
    "]"     , end_cond ;

    (*"S", intrinsic S ;
    "K", intrinsic K ;
    "I", intrinsic I ; *)

    "@" , intrinsic Fetch ;
    "!" , intrinsic Store ;

    "+" , intrinsic Add ;
    "-" , intrinsic Sub ;
    "*" , intrinsic Mul ;
    "/" , intrinsic Div ;
    "%" , intrinsic Mod ;

    "and" , intrinsic And ;
    "or"  , intrinsic Or  ;
    "xor" , intrinsic Xor ;
    "not" , intrinsic Not ;

    "="  , intrinsic Eq  ;
    "!=" , intrinsic NEq ;
    "<"  , intrinsic Lt  ;
    ">"  , intrinsic Gt  ;
    "<=" , intrinsic LtE ;
    ">=" , intrinsic GtE ;

    "dup"  , intrinsic Dup  ;
    "swap" , intrinsic Swap ;
    "nip"  , intrinsic Nip  ;
    "drop" , intrinsic Drop ;

    "."    , intrinsic EmitInt ;
    ".c"   , intrinsic Emit ;
] ;;

List.iter ( fun (k, v) -> Hashtbl.add dictionary k v ; ) prims ;;

let lookup dict word = Hashtbl.find dict word ;;


let rec parse ?(prog=[]) src =
    try 
        let word = next_word src in
        let f = try lookup dictionary word with Not_found -> lit word in
        try
            let prog' = f prog src in
            parse ~prog:prog' src
        with
        | Failure _ ->
                print_string "** Not found in dictionary: " ;
                print_endline word ;
                List.rev prog
    with
        Stream.Failure -> List.rev prog
;;



let src = Stream.of_channel stdin ;;

let prog = parse src ;;

dump prog ;;



