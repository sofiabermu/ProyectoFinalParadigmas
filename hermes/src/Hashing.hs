-- Hashing.hs — Pure SHA-256 over canonical JSON payload
module Hashing
  ( canonicalHash
  , verifyHash
  ) where

import Crypto.Hash          (SHA256(..), hashWith, Digest)
import Data.ByteArray       (convert)
import Data.ByteString      (ByteString)
import qualified Data.ByteString.Base16 as B16
import Data.Aeson           (Value, encode)
import qualified Data.ByteString.Lazy as LBS

-- | Compute SHA-256 over the UTF-8 encoded canonical JSON of a Value.
-- "Canonical" here means the default Aeson encode (keys sorted by insertion,
-- no trailing whitespace). We document this so ATLAS/Voyager can reproduce it.
canonicalHash :: Value -> ByteString
canonicalHash v =
  let lazyBytes = encode v         -- Aeson produces compact JSON
      strictBytes = LBS.toStrict lazyBytes
      digest :: Digest SHA256
      digest = hashWith SHA256 strictBytes
  in B16.encode (convert digest)

-- | Re-hash and compare against a provided hex digest.
verifyHash :: Value -> ByteString -> Bool
verifyHash v expected = canonicalHash v == expected
