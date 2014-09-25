type prim =
    | Lit of int32
    | Call of int | Jump of int | Ret
    | Dup | Nip
    | Not
    | Inc | Dec | Add | Sub
    | Comment of string

