type addr = int
type prim =
    | Lit of int32 | Str of string
    | Call of int | Jump of int | Ret
    | Imm of prim
    | Dup | Nip
    | Not
    | Eq | Lt
    | Inc | Dec | Add | Sub
    | Def
    | Comment of string

let rec string_of_prim i = match i with
    | Lit n -> "Lit " ^ Int32.to_string n
    | Str s -> "Str " ^ s
    | Call n -> "Call " ^ string_of_int n
    | Jump n -> "Jump " ^ string_of_int n
    | Ret -> "Ret"
    | Imm p -> "Imm " ^ string_of_prim p
    | Dup -> "Dup"
    | Nip -> "Nip"
    | Not -> "Not"
    | Eq  -> "Eq"
    | Lt  -> "Lt"
    | Inc -> "Inc"
    | Dec -> "Dec"
    | Add -> "Add"
    | Sub -> "Sub"
    | Def -> "Def"
    | Comment c -> "Comment " ^ c

