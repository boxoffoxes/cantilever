module Main where

import Data.Char
import Data.Maybe

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

defDict :: Dict
defDict = reverse [ ("nop", Prim Nop ),
                    ("__:", Prim Def ),
                    ("__#", Prim Imm ),
                    (";"  , Word Imm [Prim Ret] ),
                    ("1+" , Prim Inc ),
                    ("1-" , Prim Dec ) ]

data Expr = Prim Instr
          | Word Instr [Expr]
          | Suffix Expr Label
          | Error String
    deriving Show

type Label = String

type Stack = [Expr]

data VM = VM { dict :: Dict , ds :: Stack , rs :: Stack }
type Backend a = [(Instr, a)]


interpBackend :: Backend (VM -> VM)
interpBackend = [ (Nop, \vm -> vm) ]
{-           | Def
           | Ret
           | Inc
           | Dec
           | Imm
           | Lit Int
           | Str String -}


space :: Char -> Bool
space c = c <= ' '

word :: String -> (Label, String)
word s = span (not . space) $ dropWhile space s



wLookup :: Dict -> Label -> Maybe Expr
wLookup d w = lookup w d

wSuffix :: Dict -> Label -> Maybe Expr
wSuffix d w = case wLookup d sfx of
                Nothing -> Nothing
                Just i  -> Just $ Suffix i w'
    where
        sfx = ( '_' : '_' : last w : [] )
        w' = (reverse . tail . reverse) w

wNumber :: Dict -> Label -> Maybe Expr
wNumber d w = case number w of
    Nothing -> Nothing
    Just n  -> Just $ Prim (Lit n)

fromBase :: Int -> Label -> Maybe Int
fromBase b w = fromBase' b 0 w

fromBase' :: Int -> Int -> Label -> Maybe Int
fromBase' b acc []    = Just acc
fromBase' b acc (c:cs)
        | isValid c = fromBase' b (digitToInt c + acc * b) cs
        | otherwise = Nothing
    where
        isValid c = isHexDigit c && digitToInt c <= b


number :: Label -> Maybe Int
number ('0':'x':w) = fromBase 16 w 
number ('0':'o':w) = fromBase 8 w 
number ('0':'b':w) = fromBase 2 w 
number w = fromBase 10 w


wLex :: Dict -> Label -> Expr
wLex d w = case vs of 
                [] -> Error $ '"' : w ++ "\" was not found"
                _  -> fromJust $ head vs
    where
        vs = dropWhile isNothing $ [ wLookup d w , wSuffix d w, wNumber d w ]

parse :: Dict -> String -> [Expr]
parse d [] = []
parse d src = (i:parse d src')
    where
        (w, src') = word src
        i = wLex d w

{-interpret :: Backend -> Expr -> Expr
interpret bk (Prim i) 
interpret bk (Word i xs) = 
-}


main :: IO ()
main = do
    putStrLn "Hello world"

