import Data.List




data Prim = Word String | Num Int | Defn String
    deriving Show
type Prog = [Prim]
type Lexer = String -> (String, String)
type Dict = [(String, Prog)]

dropSpaces :: String -> String
dropSpaces = dropWhile (<=' ')
 
dropNextChar :: (String, String) -> (String, String)
dropNextChar (mat, rest) = (mat, tail rest)

string :: Lexer
string = dropNextChar . span (/='"') . dropSpaces

word :: Lexer
word = span (>' ') . dropSpaces


lexer :: String -> [String]
lexer = words

parseInt s = case reads s of
    [(n, "")] -> Just n
    _         -> Nothing

suffix :: String -> (String, Char)
suffix s = (reverse cs, c)
    where
        (c:cs) = reverse s

parseWord :: String -> Prim
parseWord w = case parseInt w of
    Nothing -> Word w
    Just n  -> Num n

findDefs :: Prim -> Prim
findDefs (Word w) = case suffix w of
    (w', ':') -> Defn w'
    _         -> Word w
findDefs p = p

makeDict :: Dict -> Prog -> Dict
makeDict ds (Defn d:ps) = makeDict ((d,[]):ds) ps
makeDict [] (p:ps) = error $ "Found a top-level word: " ++ show p
makeDict ((d, prog):ds) (p:ps) = makeDict ((d, p:prog):ds) ps
makeDict dict [] = dict

parser :: [String] -> Dict
parser = makeDict [] . map findDefs . map parseWord







