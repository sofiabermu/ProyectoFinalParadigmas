-- Protocol.hs — ADT definitions for the Kepler message protocol
{-# LANGUAGE DeriveGeneric     #-}
{-# LANGUAGE OverloadedStrings #-}
module Protocol where

import Data.Aeson
import Data.Aeson.Types (parseMaybe)
import Data.Text        (Text)
import GHC.Generics     (Generic)
import qualified Data.Map.Strict as Map

-- | Raw payload emitted by Voyager IX
data VoyagerReport = VoyagerReport
  { missionId      :: Text
  , coordinates    :: Coordinates
  , spectralReading :: [SpectralPoint]
  , confidence     :: Double
  , timestampUtc   :: Text
  , inferenceChain :: [Text]
  , conclusion     :: Text
  } deriving (Show, Eq, Generic)

data Coordinates = Coordinates
  { rightAscension :: Text
  , declination    :: Text
  } deriving (Show, Eq, Generic)

data SpectralPoint = SpectralPoint
  { wavelengthNm :: Double
  , intensity    :: Double
  } deriving (Show, Eq, Generic)

-- | Envelope HERMES wraps around the Voyager payload
data HermesEnvelope = HermesEnvelope
  { satelliteId       :: Text    -- "HERMES-01"
  , receivedAtUtc     :: Text
  , payloadHash       :: Text    -- hex SHA-256
  , correctedBitsCount :: Int
  } deriving (Show, Eq, Generic)

-- | Complete message as forwarded to ATLAS
-- We preserve the full original JSON object and append HERMES fields to it,
-- so we represent it as a Value with additional fields merged in.

-- Aeson instances — use camelCase field mapping
instance FromJSON Coordinates where
  parseJSON = withObject "Coordinates" $ \o ->
    Coordinates <$> o .: "right_ascension" <*> o .: "declination"

instance ToJSON Coordinates      where
  toJSON c = object ["right_ascension" .= rightAscension c, "declination" .= declination c]

instance FromJSON SpectralPoint where
  parseJSON = withObject "SpectralPoint" $ \o ->
    SpectralPoint <$> o .: "wavelength_nm" <*> o .: "intensity"

instance ToJSON SpectralPoint    where
  toJSON s = object ["wavelength_nm" .= wavelengthNm s, "intensity" .= intensity s]

instance FromJSON VoyagerReport  where
  parseJSON = withObject "VoyagerReport" $ \o ->
    VoyagerReport
      <$> o .:  "mission_id"
      <*> o .:  "coordinates"
      <*> o .:  "spectral_reading"
      <*> o .:  "confidence"
      <*> o .:  "timestamp_utc"
      <*> o .:  "inference_chain"
      <*> o .:  "conclusion"

instance ToJSON VoyagerReport    where
  toJSON r = object
    [ "mission_id"      .= missionId r
    , "coordinates"     .= coordinates r
    , "spectral_reading".= spectralReading r
    , "confidence"      .= confidence r
    , "timestamp_utc"   .= timestampUtc r
    , "inference_chain" .= inferenceChain r
    , "conclusion"      .= conclusion r
    ]
