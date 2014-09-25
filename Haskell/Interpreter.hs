module Interpreter (interpret) where

import DataTypes

primInc :: Stack -> Stack
primInc (Lit x:Lit y:st) = Lit (x+y) : st


primDef :: VM -> VM



interpret :: VM -> Instr -> VM
interpret = error "not implemented"
