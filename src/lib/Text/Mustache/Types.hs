{-|
Module      : $Header$
Description : Types and conversions
Copyright   : (c) Justus Adam, 2015
License     : LGPL-3
Maintainer  : development@justusadam.com
Stability   : experimental
Portability : POSIX
-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TupleSections         #-}
{-# LANGUAGE UnicodeSyntax         #-}
module Text.Mustache.Types
  (
  -- * Types for the Parser / Template
    AST
  , Template(..)
  , Node(..)
  , DataIdentifier(..)
  -- * Types for the Substitution / Data
  , Value(..)
  -- ** Converting
  , object
  , (~>), (~=), (~~>), (~~=)
  , ToMustache, toMustache, toTextBlock, mFromJSON
  -- ** Representation
  , Array, Object
  , Context(..)
  ) where


import           Conversion
import           Conversion.Text     ()
import qualified Data.Aeson          as Aeson
import           Data.Functor        ((<$>))
import           Data.HashMap.Strict as HM
import           Data.Scientific
import           Data.Text
import qualified Data.Text.Lazy      as LT
import qualified Data.Vector         as V
import           Prelude.Unicode

-- | Abstract syntax tree for a mustache template
type AST = [Node Text]


-- | Basic values composing the AST
data Node α
  = TextBlock α
  | Section DataIdentifier AST
  | InvertedSection DataIdentifier AST
  | Variable Bool DataIdentifier
  | Partial FilePath
  deriving (Show, Eq)


data DataIdentifier
  = NamedData [Text]
  | Implicit
  deriving (Show, Eq)


type Array = V.Vector Value
type Object = HM.HashMap Text Value
type Pair = (Text, Value)


-- | Representation of stateful context for the substitution process
data Context α = Context [α] α


-- | Internal value AST
data Value
  = Object Object
  | Array Array
  | Number Scientific
  | String Text
  | Lambda (Context Value → AST → AST)
  | Bool Bool
  | Null


instance Show Value where
  show (Lambda _)  = "Lambda Context Value → AST → Either String AST"
  show (Object o)  = show o
  show (Array a)   = show a
  show (String s)  = show s
  show (Number n)  = show n
  show (Bool b)    = show b
  show Null        = "null"


-- | Conversion class
class ToMustache ω where
  toMustache ∷ ω → Value


instance ToMustache [Char] where
  toMustache = String ∘ pack

instance ToMustache Bool where
  toMustache = Bool

instance ToMustache Char where
  toMustache = String ∘ pack ∘ return

instance ToMustache () where
  toMustache = const Null

instance ToMustache Text where
  toMustache = String

instance ToMustache LT.Text where
  toMustache = String ∘ LT.toStrict

instance ToMustache Scientific where
  toMustache = Number

instance ToMustache Value where
  toMustache = id

instance ToMustache ω ⇒ ToMustache [ω] where
  toMustache = Array ∘ V.fromList ∘ fmap toMustache

instance ToMustache ω ⇒ ToMustache (V.Vector ω) where
  toMustache = Array ∘ fmap toMustache

instance ToMustache ω ⇒ ToMustache (HM.HashMap Text ω) where
  toMustache = Object ∘ fmap toMustache

instance ToMustache (Context Value → AST → AST) where
  toMustache = Lambda

instance ToMustache (Context Value → AST → Text) where
  toMustache f = Lambda wrapper
    where wrapper c lAST = return ∘ TextBlock $ f c lAST

instance ToMustache (Context Value → AST → String) where
  toMustache f = toMustache wrapper
    where wrapper c = pack ∘ f c

instance ToMustache (AST → AST) where
  toMustache f = Lambda $ const f

instance ToMustache (AST → Text) where
  toMustache f = Lambda wrapper
    where wrapper _ = (return ∘ TextBlock) ∘ f

instance ToMustache (AST → String) where
  toMustache f = toMustache (pack ∘ f)

instance ToMustache Aeson.Value where
  toMustache (Aeson.Object o) = Object $ fmap toMustache o
  toMustache (Aeson.Array  a) = Array $ fmap toMustache a
  toMustache (Aeson.Number n) = Number n
  toMustache (Aeson.String s) = String s
  toMustache (Aeson.Bool   b) = Bool b
  toMustache (Aeson.Null)     = Null


-- | Convenience function for creating Object values.
--
-- This function is supposed to be used in conjuction with the '~>' and '~=' operators.
--
-- ==== __Examples__
--
-- @
--   data Address = Address { ... }
--
--   instance Address ToJSON where
--     ...
--
--   data Person = Person { name :: String, address :: Address }
--
--   instance ToMustache Person where
--     toMustache (Person { name, address }) = object
--       [ "name" ~> name
--       , "address" ~= address
--       ]
-- @
--
-- Here we can see that we can use the '~>' operator for values that have themselves
-- a 'ToMustache' instance, or alternatively if they lack such an instance but provide
-- an instance for the 'ToJSON' typeclass we can use the '~=' operator.
object ∷ [(Text, Value)] → Value
object = Object ∘ HM.fromList


-- | Map keys to values that provide a 'ToMustache' instance
--
-- Recommended in conjunction with the `OverloadedStrings` extension.
(~>) ∷ ToMustache ω ⇒ Text → ω → Pair
(~>) t = (t, ) ∘ toMustache


-- | Map keys to values that provide a 'ToJSON' instance
--
-- Recommended in conjunction with the `OverloadedStrings` extension.
(~=) ∷ Aeson.ToJSON ι ⇒ Text → ι → Pair
(~=) t = (t ~>) ∘ Aeson.toJSON


-- | Conceptually similar to '~>' but uses arbitrary String-likes as keys.
(~~>) ∷ (Conversion ζ Text, ToMustache ω) ⇒ ζ → ω → Pair
(~~>) = (~>) ∘ convert


-- | Conceptually similar to '~=' but uses arbitrary String-likes as keys.
(~~=) ∷ (Conversion ζ Text, Aeson.ToJSON ι) ⇒ ζ → ι → Pair
(~~=) = (~=) ∘ convert


-- | Converts arbitrary String-likes to Values
toTextBlock ∷ Conversion ζ Text ⇒ ζ → Value
toTextBlock = String ∘ convert


-- | Converts a value that can be represented as JSON to a Value.
mFromJSON ∷ Aeson.ToJSON ι ⇒ ι → Value
mFromJSON = toMustache ∘ Aeson.toJSON


{-|
  A compiled Template with metadata.
-}
data Template = Template
  { name     ∷ String
  , ast      ∷ AST
  , partials ∷ HashMap String Template
  } deriving (Show)
