type addr = int
type prim =
    | Lit of int32 | Str of string
    | Call of string | Tail of string | Jz of int | Jump of int | Ret
    | Imm of prim
    | Dup | Nip
    | Not
    | Eq | Ne | Lt | Gt | LtE | GtE
    | Inc | Dec | Add | Sub
    | Def of string
    | Comment of string

let rec string_of_prim i = match i with
    | Lit n -> "Lit " ^ Int32.to_string n
    | Str s -> "Str " ^ s
    | Call s -> "Call " ^ s
    | Tail s -> "Tail " ^ s
    | Jump n -> "Jump " ^ string_of_int n
    | Ret -> "Ret"
    | Imm p -> "Imm " ^ string_of_prim p
    | Dup -> "Dup"
    | Nip -> "Nip"
    | Not -> "Not"
    | Eq  -> "Eq"
    | Ne     -> "Ne"
    | Lt     -> "Lt"
    | Gt     -> "Gt"
    | LtE    -> "LtE"
    | GtE    -> "GtE"
    | Inc -> "Inc"
    | Dec -> "Dec"
    | Add -> "Add"
    | Sub -> "Sub"
    | Def s -> "Def " ^ s
    | Comment c -> "Comment " ^ c

