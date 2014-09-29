type prim =
    | Lit of int32 | Str of string
    | Call of int | Jump of int | Ret
    | Imm of prim
    | Dup | Nip
    | Not
    | Eq | Lt
    | Inc | Dec | Add | Sub
    | Comment of string

