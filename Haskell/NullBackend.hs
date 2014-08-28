module NullBackend where

import DataTypes



nullBackend :: Backend String
nullBackend = [
   (Nop, ".nop"),
   (, ".nop"),
   (Nop, ".nop"),
   (Nop, ".nop"),
   (Nop, ".nop"),
]

translateInstr :: Instr -> String
translateInstr Nop = "nop"
translateInstr Def = "__:"
translateInstr Ret = ";"
translateInstr Inc = "1+"
translateInstr Dec = "1-"
translateInstr Imm = "__#"
translateInstr (Lit i) = show i
translateInstr (Str s) = show s

translateExpr :: Expr -> String
translateExpr (Prim i) = translateInstr i
translateExpr (Suffix e l) = 
translateExpr (Word i es) = "[ " ++ map translateInstr es ++ " ]"

