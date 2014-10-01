open Printf
open Instructions


type settings = {
    mutable compile : bool ;
    mutable compiler : prim list -> string list ;
    mutable interpreter : prim list -> string list ;
    mutable source : in_channel ;
    mutable dest : out_channel ;
}

let settings = {
    compile = false ; 
    compiler = X86CodeGen.compile ;
    interpreter = Interpreter.eval ;
    source = stdin ;
    dest = stdout ;
}


let is_whitespace c = compare (Some ' ') c >= 0 ;;
let is_not_whitespace c = not ( is_whitespace c ) ;;
let is_newline c = compare (Some '\n') c == 0 || compare (Some '\r') c == 0 ;;
let is_closing_paren c = compare (Some ')') c = 0 ;;
let is_closing_quote c = compare (Some '"') c = 0 ;;

let consume_to pred st =
    let buf = Buffer.create 16 in
    while not ( pred (Stream.peek st) ) do
        Buffer.add_char buf (Stream.next st) ;
    done ;
    Buffer.contents buf
;;

(* quote_to is like consume_to, but also drops the final character *)
let quote_to pred st =
    let str = consume_to pred st in
    ignore (Stream.next st); 
    str
;;

let next_word st = 
    ignore ( consume_to is_not_whitespace st ) ;
    consume_to is_whitespace st
;;

let strip_suffix word = 
    let split_at = String.length word - 1 in
    let suf = "__" ^ String.sub word split_at 1 in
    let word' = String.sub word 0 split_at in
    (word', suf)
;;

let parse_number word =
    Lit ( Int32.of_string word )
;;

let parse_prim word st = match word with
    | "true"  -> Lit (Int32.minus_one)
    | "false" -> Lit (Int32.zero)

    | "s\""   -> Str ( quote_to is_closing_quote st )

    | "dup"   -> Dup
    | "not"   -> Not

    | "1+"    -> Inc
    | "1-"    -> Dec
    | "+"     -> Add
    | "-"     -> Sub

    | "="     -> Eq
    | "<"     -> Lt

    | ";"     -> Ret

    | "--"    -> Comment ( consume_to is_newline st )
    | "("     -> Comment ( quote_to is_closing_paren st )

    | "__:"   -> Def
    | _       -> raise Not_found
;;

let rec parse ?(prog=[]) src = try
    let word = next_word src in
    let i = try
        parse_prim word src
    with Not_found -> try
        parse_number word
    with Failure _ ->
        let (word', suf) = strip_suffix word in
        let ins = parse_prim suf src in
        Imm ins  (* TODO: handle arg *)
    in
    parse ~prog:(i::prog) src
with
    Stream.Failure -> List.rev prog
;;

let usage () = printf "Yer doin' it all wrong!\n" ; exit 0 ;;

let rec parse_args args =
    match args with
    | [] -> ()
    | "-c" :: args' -> settings.compile <- true ; parse_args args'
    | "-b" :: "x86" :: args' ->
            settings.compiler <- X86CodeGen.compile ; parse_args args'
    | "-b" :: "null" :: args' ->
            settings.compiler <- CantileverCodeGen.compile ; parse_args args'
    | "-h" :: _ | "--help" :: _ -> usage () ;
    | opt :: _ when opt.[0] = '-' -> usage () ;
    | file :: [] when String.length file > 0 -> 
            settings.source <- open_in file ;
    | _ -> usage () ;
;;

let main = 
    parse_args ( List.tl ( Array.to_list Sys.argv ) ) ;
    let src = Stream.of_channel settings.source in
    let prog = parse src in
    match settings.compile with 
    | true -> 
        let asm  = settings.compiler prog in
        List.iter print_endline asm ;
    | false ->
        let results = settings.interpreter prog in
        List.iter print_endline results ;
;;

main
