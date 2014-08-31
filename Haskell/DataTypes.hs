module DataTypes where

type Dict = [(String, Expr)]

data Instr = Nop
           | Def
           | Ret
           | Inc
           | Dec
           | Imm
           | Lit Int
           | Str String
    deriving Show

data Expr = Prim Instr
          | Word Instr [Expr]
          | Suffix Expr Label
          | Error String Context
    deriving Show

data VM = VM { dict :: Dict , ds :: Stack , rs :: Stack, heap :: Heap }
    deriving Show
  
type Addr = Int
type Label = String
type Context = String
type Stack = [Instr]
type Heap = [(Addr, [Expr])]

type Backend a = [(Instr, a)]

