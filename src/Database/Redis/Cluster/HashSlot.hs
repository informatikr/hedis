{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE OverloadedStrings #-}
module Database.Redis.Cluster.HashSlot(HashSlot, keyToSlot) where

import Data.Bits((.&.))
import qualified Data.ByteString.Char8 as Char8
import qualified Data.ByteString as BS
import Data.Word(Word16)
import qualified Data.Digest.CRC16  as CRC16

newtype HashSlot = HashSlot Word16 deriving (Num, Eq, Ord, Real, Enum, Integral, Show)

numHashSlots :: Word16
numHashSlots = 16384

-- | Compute the hashslot associated with a key
keyToSlot :: BS.ByteString -> HashSlot
keyToSlot = HashSlot . (.&.) (numHashSlots - 1) . crc16 . findSubKey

-- | Find the section of a key to compute the slot for.
findSubKey :: BS.ByteString -> BS.ByteString
findSubKey key = case Char8.break (=='{') key of
  (whole, "") -> whole
  (_, xs) -> case Char8.break (=='}') (Char8.tail xs) of
    ("", _) -> key
    (subKey, _) -> subKey

crc16 :: BS.ByteString -> Word16
crc16 = BS.foldl (CRC16.crc16_update 0x1021 False) 0

