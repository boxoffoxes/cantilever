module Parse where

import ParseLib

isNonSpace :: Char -> Bool
isNonSpace = (> ' ')

nonSpace :: Parser Char
nonSpace = satisfy isNonSpace

space :: Parser Char
space = satisfy ( not . isNonSpace )

word :: Parser String
word = maybeSome space |> atLeastOne nonSpace

parse :: Parser [String]
parse = case maybeSome word 
