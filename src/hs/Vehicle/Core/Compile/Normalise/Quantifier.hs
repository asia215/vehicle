{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PatternSynonyms #-}

module Vehicle.Core.Normalise.Quantifier
  ( normQuantifier
  , Quantifier(..)
  ) where

import Control.Monad.Error.Class (throwError)
import Data.Range (Range (..), fromRanges, intersection, union, invert, lbi, lbe, ubi, ube, mergeRanges)
import Data.Text (Text)
import Vehicle.Core.AST
import Vehicle.Core.Normalise.Core
import Vehicle.Prelude (Provenance)

-----------
-- Types --
-----------
-- FIX THIS WHEN TYPE-CHECKER UP AND RUNNING

type TempType = Text

getType :: NormExpr ann -> TempType
getType _ = "Bool"

-----------------
-- Quantifiers --
-----------------

data Quantifier = Any | All

quantifierOp :: Quantifier -> Builtin 'EXPR
quantifierOp Any = EAny
quantifierOp All = EAll

linkingOp :: Quantifier -> Builtin 'EXPR
linkingOp Any = EOr
linkingOp All = EAnd

-------------------
-- Normalisation --
-------------------

normQuantifier
  :: (MonadNorm m)
  => Quantifier
  -> NormExpr ann
  -> NormExpr ann
  -> ann 'EXPR -> ann 'EXPR -> ann 'EXPR
  -> Provenance
  -> m (NormExpr ann)
normQuantifier quant domain condition ann0 ann1 ann2 p = case getQuantifierValues domain ann0 of
  -- Cannot expand quantifier
  Nothing -> return $ EOp2 (quantifierOp quant) domain condition ann0 ann1 ann2
  -- Could expand quantifier but domain appears to be trivially empty
  Just [] -> throwError $ EmptyQuantifierDomain p
  -- Can expand quantifier with non-empty domain
  Just es ->
    let linkOp x y = EOp2 (linkingOp quant) x y ann0 ann1 ann2
        substValue v = DeBruijn.subst v condition
    in  return $ foldr1 linkOp (map substValue es)

getQuantifierValues
  :: NormExpr ann
  -> ann 'EXPR
  -> Maybe [NormExpr ann]
getQuantifierValues domain ann = case getType domain of
  "Bool" -> Just [mkBool True ann, mkBool False ann]
  "Int"  -> Just $ getIntQuantifierValues domain ann
  _      -> Nothing

getIntQuantifierValues
  :: NormExpr ann -- ^ Expression describing the domain of the quantified integer variable.
  -> ann 'EXPR    -- ^ The annotation accompanying the quantifier.
  -> [NormExpr ann]
getIntQuantifierValues domain ann =
  let ranges = mergeRanges $ getIntVariableRanges 0 domain in
    -- TODO: there should probably be a size check here.
    map (ELitInt ann) (fromRanges ranges)

-- | Attempts to find bounds on the provided integer variable.
--
-- TODO: this should probably be eventually implemented via an SMT solver,
--       but this naive check will do for the moment.
--
getIntVariableRanges
  :: Int          -- ^ Current deBruijn level
  -> NormExpr ann -- ^ Fully normalised expression that may contain bounds on the variable
  -> [Range Integer]
getIntVariableRanges l (EOp2 EEq (ELitInt _ i) (EVar _ v) _ _ _)
  | toIndex v == l = [SingletonRange i]
getIntVariableRanges l (EOp2 EEq (EVar _ v) (ELitInt _ i) _ _ _)
  | toIndex v == l = [SingletonRange i]
getIntVariableRanges l (EOp2 ELe (ELitInt _ i) (EVar _ v) _ _ _)
  | toIndex v == l = [ubi i]
getIntVariableRanges l (EOp2 ELe (EVar _ v) (ELitInt _ i) _ _ _)
  | toIndex v == l = [lbi i]
getIntVariableRanges l (EOp2 ELt (ELitInt _ i) (EVar _ v) _ _ _)
  | toIndex v == l = [ube i]
getIntVariableRanges l (EOp2 ELt (EVar _ v) (ELitInt _ i) _ _ _)
  | toIndex v == l = [lbe i]
getIntVariableRanges l (EOp1 ENot e _ _)
  = invert (getIntVariableRanges l e)
getIntVariableRanges l (EOp2 EAnd e1 e2 _ _ _)
  = getIntVariableRanges l e1 `intersection` getIntVariableRanges l e2
getIntVariableRanges l (EOp2 EOr e1 e2 _ _ _)
  = getIntVariableRanges l e1 `union` getIntVariableRanges l e2
getIntVariableRanges _ _
  = [InfiniteRange]
