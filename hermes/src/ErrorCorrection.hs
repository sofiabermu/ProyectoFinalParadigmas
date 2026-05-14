-- ErrorCorrection.hs — Triple-repetition code error correction
--
-- Scheme: each bit is encoded as 3 copies (000 or 111).
-- Decoder: majority vote per triple. A corrected bit is one where
-- the triple is not all-same (i.e., one bit differed from the majority).
-- This detects and corrects 1-bit errors per 3-bit group.
--
-- Applied at the byte level over the raw JSON ByteString:
--   encode: each byte -> 3 identical bytes
--   decode: every 3 bytes -> majority-vote byte, count corrections
--
-- For a relay node, we only run the decode side on incoming bytes,
-- since we trust the upstream sender encoded with the same scheme.
-- In practice the "error injection" would come from a noisy channel;
-- here we just implement the codec and report correctedBitsCount.
module ErrorCorrection
  ( encodeRepetition
  , decodeRepetition
  , CorrectionResult(..)
  ) where

import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import Data.Word       (Word8)
import Data.List       (maximumBy)
import Data.Ord        (comparing)

data CorrectionResult = CorrectionResult
  { decodedBytes      :: ByteString
  , correctedBitCount :: Int
  } deriving (Show, Eq)

-- | Encode: each byte is repeated 3 times.
encodeRepetition :: ByteString -> ByteString
encodeRepetition = BS.concatMap (\b -> BS.pack [b, b, b])

-- | Decode: take triplets, majority-vote each one.
-- Returns the decoded bytes and number of corrected bits.
decodeRepetition :: ByteString -> CorrectionResult
decodeRepetition bs =
  let triples  = chunksOf 3 (BS.unpack bs)
      results  = map decodeTriplet triples
      decoded  = BS.pack (map fst results)
      corrected = sum (map snd results)
  in CorrectionResult decoded corrected

-- | Majority vote over a triplet. Returns (byte, corrections).
-- A "correction" is counted when the triplet is not unanimous.
decodeTriplet :: [Word8] -> (Word8, Int)
decodeTriplet [a, b, c] =
  let winner = majorityByte a b c
      corrections = if a == b && b == c then 0 else 1
  in (winner, corrections)
decodeTriplet xs =
  -- Partial triplet (trailing bytes) — pass through unchanged
  let winner = if null xs then 0 else head xs
  in (winner, 0)

majorityByte :: Word8 -> Word8 -> Word8 -> Word8
majorityByte a b c
  | a == b    = a
  | a == c    = a
  | otherwise = b

chunksOf :: Int -> [a] -> [[a]]
chunksOf _ [] = []
chunksOf n xs = let (h, t) = splitAt n xs in h : chunksOf n t
