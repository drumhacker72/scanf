{-# LANGUAGE GADTs #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TypeOperators #-}

module Text.Scanf.Internal where

import Data.Char (isSpace)
import Text.ParserCombinators.ReadP (ReadP, get, munch, readP_to_S, readS_to_P, skipSpaces)

import qualified Text.ParserCombinators.ReadP as ReadP

-- | A pretty pair type to build lists with values of different types. 
-- Remember to close lists with @()@.
--
-- @
-- 3 ':+' "14" ':+' () :: 'Int' ':+' 'String' ':+' ()
-- @
data a :+ b = a :+ b
  deriving (Eq, Ord, Show)

infixr 1 :+

-- | Typed @'scanf'@/@'printf'@ format strings.
-- They can be built using the 'Text.Scanf.fmt' quasiquote or
-- with the 'fmt_' function and format combinators.
data Format t where
  Empty :: Format ()
  Constant :: String -> Format t -> Format t
  Whitespace :: String -> Format t -> Format t
  Readable :: (Read a, Show a) => Format t -> Format (a :+ t)
  String :: Format t -> Format (String :+ t)  -- whitespace delimited
  Char :: Format t -> Format (Char :+ t)

deriving instance Show (Format t)

emptyFmt :: Format ()
emptyFmt = Empty

-- | Construct a format string. This is an alternative to 'Text.Scanf.fmt'
-- that doesn't rely on Template Haskell.
--
-- The components of a format string are composed using @('.')@ (function
-- composition) and @('%')@ (wrapper for constant strings).
--
-- @
-- 'fmt_' ('int' '.' \" lazy \" '%' 'string' '.' \" and \" '%' 'int' '.' \" strict \" '%' 'string')
--   :: 'Format' ('Int' ':+' 'String' ':+' 'Int' ':+' 'String' ':+' ())
-- @
fmt_ :: (Format () -> Format t) -> Format t
fmt_ f = f emptyFmt

-- | Append a constant string to a format string component.
--
-- N.B.: in 'scanf', spaces in the format string match any number of whitespace
-- character until the next nonspace character.
(%) :: String -> (Format t -> Format q) -> Format t -> Format q
(%) s f = constant s . f

infixr 9 %

-- | Append a constant string to a format string.
constant :: String -> Format t -> Format t
constant "" f = f
constant s@(c : _) f | isSpace c =
  let (s0, s') = span isSpace s
  in whitespace s0 (constant s' f)
constant s f =
  let (s0, s') = break isSpace s
  in constant' s0 (constant s' f)

-- | Append a constant string with no whitespace to a format string.
constant' :: String -> Format t -> Format t
constant' s (Constant s' f) = Constant (s ++ s') f
constant' "" f = f
constant' s f = Constant s f

-- | Append a constant whitespace string to a format string.
whitespace :: String -> Format t -> Format t
whitespace s (Whitespace s' f) = Whitespace (s ++ s') f
whitespace s f = Whitespace s f

readable :: (Read a, Show a) => Format t -> Format (a :+ t)
readable = Readable

-- | Format an 'Integer'.
integer :: Format t -> Format (Integer :+ t)
integer = Readable

-- | Format an 'Int'.
int :: Format t -> Format (Int :+ t)
int = Readable

-- | Format a 'Double'.
double :: Format t -> Format (Double :+ t)
double = Readable

-- | Format a 'String'.
string :: Format t -> Format (String :+ t)
string = String

-- | Format a 'Char'.
char :: Format t -> Format (Char :+ t)
char = Char

fromFormat :: Format t -> ReadP t
fromFormat (Constant z f) = do
  _ <- ReadP.string z
  fromFormat f
fromFormat (Readable f) = do
  a <- readS_to_P reads
  (a :+) <$> fromFormat f
fromFormat (String f) = do
  s0 <- munch (not . isSpace)
  (s0 :+) <$> fromFormat f
fromFormat (Char f) = do
  c <- get
  (c :+) <$> fromFormat f
fromFormat (Whitespace _ f) = do
  skipSpaces
  fromFormat f
fromFormat Empty = return ()

-- | Parse a string according to a format string.
--
-- @
-- 'scanf' ['Text.Scanf.fmt'|Hello %s|] \"Hello world!\" :: ReadS ('String' ':+' ())
--   = [(\"world!\" ':+' (), \"\")]
-- @
scanf :: Format t -> ReadS t
scanf f = readP_to_S $ fromFormat f

-- | Print a string according to a format string.
--
-- @
-- 'printf' ['Text.Scanf.fmt'|Hello %s|] (\"everyone!\" ':+' ())
--   = \"Hello everyone!\" 
-- @
printf :: Format t -> t -> String
printf (Constant z f) t = z ++ printf f t
printf (Readable f) (a :+ t) = show a ++ printf f t
printf (String f) (s :+ t) = s ++ printf f t
printf (Char f) (c :+ t) = c : printf f t
printf (Whitespace s f) t = s ++ printf f t
printf Empty _ = ""
