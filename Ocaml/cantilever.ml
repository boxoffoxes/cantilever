open Printf
open Instructions

let src = Stream.of_channel stdin ;;

let is_whitespace c = compare (Some ' ') c >= 0 ;;
let is_not_whitespace c = not ( is_whitespace c ) ;;
let is_newline c = compare (Some '\n') c == 0 || compare (Some '\r') c == 0 ;;
let is_closing_paren c = compare (Some ')') c = 0 ;;

let consume_to pred st =
    let buf = Buffer.create 16 in
    while not ( pred (Stream.peek st) ) do
        Buffer.add_char buf (Stream.next st) ;
    done ;
    Buffer.contents buf
;;

let comment_to pred st =
    let str = consume_to pred st in
    ignore (Stream.next st); 
    str
;;

let next_word st = 
    ignore ( consume_to is_not_whitespace st ) ;
    consume_to is_whitespace st
;;

let parse_number word =
    Lit ( Int32.of_string word )
;;

let parse_prim word st = match word with
    | "true"  -> Lit (Int32.minus_one)
    | "false" -> Lit (Int32.zero)

    | "dup"   -> Dup
    | "not"   -> Not

    | "1+"    -> Inc
    | "1-"    -> Dec
    | "+"     -> Add
    | "-"     -> Sub

    | "--"    -> Comment ( consume_to is_newline st )
    | "("     -> Comment ( comment_to is_closing_paren st )

    | _       -> raise Not_found
;;

let rec parse ?(prog=[]) src = try
    let word = next_word src in
    let i = try
        parse_prim word src
    with Not_found ->
        parse_number word
    in
    parse ~prog:(i::prog) src
with
    Stream.Failure -> List.rev prog
;;

module type CANTILEVER_BACKEND = sig
    val compile : prim list -> string list
end;;



module Backend = functor ( Gen : CANTILEVER_BACKEND ) ->
struct
    let compile = Gen.compile
end;;


let main = 
    let module Interp  = Backend(Interpreter) in
    let module Backend = Backend(X86CodeGen) in
    (*let module Backend = Backend(CantileverCodeGen) in*)
    let prog = parse src in
    let asm  = Backend.compile prog in
    List.iter print_endline asm ;
;;

main
