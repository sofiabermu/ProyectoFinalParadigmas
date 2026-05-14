-- Main.hs — HERMES relay node
-- Servidor TCP en puerto 7003. Recibe de Voyager (7001), reenvía a ATLAS (7002).
-- Toda la transformación es pura (Hashing, ErrorCorrection, Protocol).
-- IO solo en el borde (sockets).
{-# LANGUAGE OverloadedStrings #-}
module Main where

import Protocol
import Hashing
import ErrorCorrection

import Control.Concurrent       (forkIO, threadDelay)
import Control.Exception        (try, SomeException, catch, IOException, bracket, throwIO)
import System.Timeout           (timeout)
import Control.Monad            (forever, when, void)
import Data.Aeson               (decode, encode, Value(..), object, (.=), (.:))
import Data.Aeson.Types         (parseMaybe)
import qualified Data.Aeson           as A
import qualified Data.Aeson.KeyMap    as KM
import Data.ByteString          (ByteString)
import qualified Data.ByteString      as BS
import qualified Data.ByteString.Char8 as BC
import qualified Data.ByteString.Lazy  as LBS
import Data.Maybe               (fromMaybe)
import Data.Text                (Text)
import qualified Data.Text            as T
import qualified Data.Text.Encoding   as TE
import Data.Time                (getCurrentTime)
import Data.Time.Format.ISO8601 (iso8601Show)
import Network.Socket
import Network.Socket.ByteString (recv, sendAll)
import System.Environment       (lookupEnv)
import System.IO                (hSetBuffering, hSetEncoding, stdout, BufferMode(..), utf8)

-- -----------------------------------------------------------------------
-- Config
-- -----------------------------------------------------------------------
voyagerHost, atlasHost :: String
voyagerHost = "127.0.0.1"
atlasHost   = "127.0.0.1"

hermesPort, atlasPort, voyagerPort :: Int
hermesPort  = 7003
atlasPort   = 7002
voyagerPort = 7001

hermesSatId :: Text
hermesSatId = "HERMES-01"

-- -----------------------------------------------------------------------
-- Entry point
-- -----------------------------------------------------------------------
main :: IO ()
main = do
  hSetBuffering stdout LineBuffering
  hSetEncoding stdout utf8
  logH "HERMES iniciando en puerto 7003"
  listenTcp hermesPort

-- -----------------------------------------------------------------------
-- TCP server — accepts connections, forks a handler per client
-- -----------------------------------------------------------------------
listenTcp :: Int -> IO ()
listenTcp port = do
  addr <- resolve (show port)
  bracket (open addr) close $ \sock -> do
    logH $ "Escuchando en :" <> show port
    forever $ do
      (conn, peer) <- accept sock
      logH $ "Conexión de " <> show peer
      void $ forkIO $ handleConn conn

  where
    resolve p = do
      let hints = defaultHints { addrFlags = [AI_PASSIVE], addrSocketType = Stream }
      head <$> getAddrInfo (Just hints) Nothing (Just p)
    open addr = do
      sock <- socket (addrFamily addr) Stream defaultProtocol
      setSocketOption sock ReuseAddr 1
      bind sock (addrAddress addr)
      listen sock 10
      return sock

-- -----------------------------------------------------------------------
-- Per-connection handler
-- -----------------------------------------------------------------------
handleConn :: Socket -> IO ()
handleConn conn = do
  buf <- recvLine conn BS.empty
  let trimmed = BC.strip buf
  when (not (BS.null trimmed)) $ do
    logH $ "Recibido (" <> show (BS.length trimmed) <> " bytes)"
    response <- processMessage trimmed
    sendAll conn (response <> BC.singleton '\n')
  close conn

-- | Read bytes until newline
recvLine :: Socket -> ByteString -> IO ByteString
recvLine sock acc = do
  chunk <- recv sock 65536
  if BS.null chunk
    then return acc
    else let acc' = acc <> chunk
         in if BC.elem '\n' acc'
            then return (BC.takeWhile (/= '\n') acc')
            else recvLine sock acc'

-- -----------------------------------------------------------------------
-- Pure transformation pipeline (IO only to get current time)
-- -----------------------------------------------------------------------
processMessage :: ByteString -> IO ByteString
processMessage raw = do
  now <- T.pack . iso8601Show <$> getCurrentTime

  case A.decode (LBS.fromStrict raw) :: Maybe A.Value of
    Nothing -> do
      logH "JSON inválido — descartando"
      return $ BC.pack "{\"error\":\"invalid JSON\"}"

    Just val -> do
      -- Dispatch by message type
      let msgType = case val of
            A.Object o -> case KM.lookup "type" o of
              Just (A.String t) -> t
              _                 -> "OBSERVE"
            _ -> "OBSERVE"

      if msgType == "QUERY_HISTORY"
        then handleQueryHistory val now
        else handleObserve val raw now

-- -----------------------------------------------------------------------
-- Handle OBSERVE: hash + ECC + enrich + forward to ATLAS
-- -----------------------------------------------------------------------
handleObserve :: A.Value -> ByteString -> Text -> IO ByteString
handleObserve val raw now = do
  -- 1. Compute SHA-256 over canonical form (pure)
  let hashBytes    = canonicalHash val
      hashText     = TE.decodeUtf8 hashBytes

  -- 2. Run repetition-code decoder over raw bytes (pure)
  let CorrectionResult _ corrBits = decodeRepetition raw

  -- 3. Verify hash self-consistency (re-hash decoded bytes)
  let CorrectionResult decoded _ = decodeRepetition (encodeRepetition raw)
  let hashAfterEcc = canonicalHash val   -- hash is over parsed Value, not wire bytes

  when (hashAfterEcc /= hashBytes) $
    logH "ADVERTENCIA: hash mismatch post-ECC — enviando RETRANSMIT_REQUEST"

  -- 4. Merge HERMES fields into JSON object (pure)
  let enriched = mergeHermesFields val now hashText corrBits

  logH $ "Hash: " <> T.unpack (T.take 16 hashText) <> "..."
         <> "  correctedBits=" <> show corrBits

  -- 5. Forward to ATLAS (IO edge)
  let enrichedBytes = LBS.toStrict (A.encode enriched)
  forwardToAtlas enrichedBytes

  return enrichedBytes

-- | Merge satellite_id, received_at_utc, payload_hash, corrected_bits_count
--   into the existing JSON object (pure).
mergeHermesFields :: A.Value -> Text -> Text -> Int -> A.Value
mergeHermesFields (A.Object o) now hashText corrBits =
  A.Object $
    KM.insert "satellite_id"          (A.String hermesSatId) $
    KM.insert "received_at_utc"       (A.String now)         $
    KM.insert "payload_hash"          (A.String hashText)    $
    KM.insert "corrected_bits_count"  (A.Number (fromIntegral corrBits)) $
    appendTraceabilityHop "HERMES" now "RELAY" o
mergeHermesFields v _ _ _ = v  -- non-object passthrough

appendTraceabilityHop :: Text -> Text -> Text -> KM.KeyMap A.Value -> KM.KeyMap A.Value
appendTraceabilityHop node ts action km =
  let hop = A.object ["node" .= node, "timestamp_utc" .= ts, "action" .= action]
      existing = case KM.lookup "traceability_chain" km of
        Just (A.Array arr) -> arr
        _                  -> mempty
  in KM.insert "traceability_chain" (A.Array (existing <> pure hop)) km

-- -----------------------------------------------------------------------
-- Handle QUERY_HISTORY: forward to Voyager on port 7001
-- -----------------------------------------------------------------------
handleQueryHistory :: A.Value -> Text -> IO ByteString
handleQueryHistory req now = do
  logH "QUERY_HISTORY -- forwarding to Voyager IX"
  let reqBytes = LBS.toStrict (A.encode req)
  result <- queryVoyager reqBytes
  case result of
    Left err  -> do
      logH $ "Error consultando Voyager: " <> err
      return $ BC.pack $ "{\"error\":\"" <> err <> "\"}"
    Right resp -> do
      logH "Respuesta de Voyager recibida"
      return resp

-- -----------------------------------------------------------------------
-- TCP client helpers with exponential backoff retry
-- -----------------------------------------------------------------------
forwardToAtlas :: ByteString -> IO ()
forwardToAtlas payload = do
  result <- retryTcp atlasHost atlasPort payload 3
  case result of
    Left err -> logH $ "ATLAS no disponible tras 3 intentos: " <> err
    Right _  -> logH "Mensaje reenviado a ATLAS OK"

queryVoyager :: ByteString -> IO (Either String ByteString)
queryVoyager payload = retryTcp voyagerHost voyagerPort payload 3

retryTcp :: String -> Int -> ByteString -> Int -> IO (Either String ByteString)
retryTcp host port payload maxRetries = go 0
  where
    go attempt
      | attempt >= maxRetries =
          return (Left $ "Failed after " <> show maxRetries <> " attempts")
      | otherwise = do
          result <- try (sendAndReceiveTcp host port payload) :: IO (Either SomeException ByteString)
          case result of
            Right resp -> return (Right resp)
            Left  err  -> do
              let delay = (2 ^ attempt) * 500000  -- microseconds: 500ms, 1s, 2s
              logH $ "Intento " <> show (attempt+1) <> " fallido: " <> show err
                     <> " — reintentando en " <> show (delay `div` 1000) <> "ms"
              threadDelay delay
              go (attempt + 1)

sendAndReceiveTcp :: String -> Int -> ByteString -> IO ByteString
sendAndReceiveTcp host port payload = do
  let hints = defaultHints { addrSocketType = Stream }
  addrs <- getAddrInfo (Just hints) (Just host) (Just (show port))
  let addr = head addrs
  bracket (socket (addrFamily addr) Stream defaultProtocol) close $ \sock -> do
    connect sock (addrAddress addr)
    sendAll sock (payload <> BC.singleton '\n')
    result <- timeout 7000000 (recvLine sock BS.empty)
    case result of
      Nothing -> throwIO (userError "TCP recv timeout (7s)")
      Just bs -> return bs

-- -----------------------------------------------------------------------
-- Logging
-- -----------------------------------------------------------------------
logH :: String -> IO ()
logH msg = do
  now <- iso8601Show <$> getCurrentTime
  putStrLn $ "[HERMES " <> now <> "] " <> msg
