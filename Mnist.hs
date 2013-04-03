module Mnist (
    Image(..)
  , normalisedData
  , readImages
  , readImages'
  , writeImages
  , writeImage
  , readLabels
  , writeLabels
  , serialiseHeader
  , toMatrix)
  where

import qualified Data.ByteString.Lazy as BL
import Data.Binary.Get
import Data.Binary.Put
import Data.Word
import qualified Data.List.Split as S
import Numeric.LinearAlgebra

data Image = Image {
      iRows :: Int
    , iColumns :: Int
    , iPixels :: [Word8]
    } deriving (Eq, Show)

toMatrix :: Image -> Matrix Double
toMatrix image = (r><c) p :: Matrix Double
  where r = iRows image
        c = iColumns image
        p = map fromIntegral (iPixels image)

{-
toColumnVector :: Image -> Matrix Double
toColumnVector i = (r><1) q :: Matrix Double
  where r = Mnist.rows i * Mnist.columns i
        p = map fromIntegral (pixels i)
        q = map normalise p
-}

normalisedData :: Image -> [Double]
normalisedData image = map normalisePixel (iPixels image)

--normalisedData :: Image -> [Double]
--normalisedData i = map (/m) x
--    where x = map normalisePixel (pixels i)
--          m = sqrt( sum (zipWith (*) x x))

normalisePixel :: Word8 -> Double
normalisePixel p = (fromIntegral p) / 255.0

-- MNIST label file format
--
-- [offset] [type]          [value]          [description]
-- 0000     32 bit integer  0x00000801(2049) magic number (MSB first)
-- 0004     32 bit integer  10000            number of items
-- 0008     unsigned byte   ??               label
-- 0009     unsigned byte   ??               label
-- ........
-- xxxx     unsigned byte   ??               label
--
-- The labels values are 0 to 9.

deserialiseLabels :: Get (Word32, Word32, [Word8])
deserialiseLabels = do
  magicNumber <- getWord32be
  count <- getWord32be
  labelData <- getRemainingLazyByteString
  let labels = BL.unpack labelData
  return (magicNumber, count, labels)

readLabels :: FilePath -> IO [Int]
readLabels filename = do
  content <- BL.readFile filename
  let (_, _, labels) = runGet deserialiseLabels content
  return (map fromIntegral labels)

serialiseLabels :: Word32 -> Word32 -> [Word8] -> Put
serialiseLabels magicNumber count labels = do
  putWord32be magicNumber
  putWord32be count
  mapM_ putWord8 labels

writeLabels :: FilePath -> [Int] -> IO ()
writeLabels fileName labels = do
  let content = runPut $ serialiseLabels
                         0x00000801
                         (fromIntegral $ length labels)
                         (map fromIntegral labels)
  BL.writeFile fileName content

-- MNIST Image file format
--
-- [offset] [type]          [value]          [description]
-- 0000     32 bit integer  0x00000803(2051) magic number
-- 0004     32 bit integer  ??               number of images
-- 0008     32 bit integer  28               number of rows
-- 0012     32 bit integer  28               number of columns
-- 0016     unsigned byte   ??               pixel
-- 0017     unsigned byte   ??               pixel
-- ........
-- xxxx     unsigned byte   ??               pixel
--
-- Pixels are organized row-wise. Pixel values are 0 to 255. 0 means background (white), 255
-- means foreground (black).

deserialiseHeader :: Get (Word32, Word32, Word32, Word32, [[Word8]])
deserialiseHeader = do
  magicNumber <- getWord32be
  imageCount <- getWord32be
  r <- getWord32be
  c <- getWord32be
  packedData <- getRemainingLazyByteString
  let len = fromIntegral (r * c)
  let unpackedData = S.chunksOf len (BL.unpack packedData)
  return (magicNumber, imageCount, r, c, unpackedData)

deserialiseHeader' :: Integer -> Integer -> Get (Word32, Word32, Word32, Word32, [[Word8]])
deserialiseHeader' start end = do
  magicNumber <- getWord32be
  imageCount <- getWord32be
  r <- getWord32be
  c <- getWord32be
  let len = fromIntegral (r * c)
  _ <- getLazyByteString (fromIntegral $ len * start)
  packedData <- getLazyByteString (fromIntegral $ len * (end - start + 1))
  let unpackedData = S.chunksOf (fromIntegral len) (BL.unpack packedData)
  return (magicNumber, imageCount, r, c, unpackedData)

readImages :: FilePath -> IO [Image]
readImages filename = do
  content <- BL.readFile filename
  let (_, _, r, c, unpackedData) = runGet deserialiseHeader content
  return (map (Image (fromIntegral r) (fromIntegral c)) unpackedData)

readImages' :: FilePath -> Integer -> Integer -> IO [Image]
readImages' filename start end = do
  content <- BL.readFile filename
  let (_, _, r, c, unpackedData) = runGet (deserialiseHeader' start end) content
  return (map (Image (fromIntegral r) (fromIntegral c)) unpackedData)

serialiseHeader :: Word32 -> Word32 -> Word32 -> Word32 -> [[Word8]] -> Put
serialiseHeader magicNumber imageCount nRows nCols iss = do
  putWord32be magicNumber
  putWord32be imageCount
  putWord32be nRows
  putWord32be nCols
  mapM_ putWord8 $ concat iss

writeImages :: FilePath -> [Image] -> IO ()
writeImages fileName is = do
  let content = runPut $ serialiseHeader
                         0x00000803
                         (fromIntegral $ length is)
                         (fromIntegral $ iRows $ head is)
                         (fromIntegral $ iColumns $ head is)
                         (map iPixels is)
  BL.writeFile fileName content

writeImage :: FilePath -> Image -> IO ()
writeImage fileName i = do
 let content = runPut $ mapM_ putWord8 $ iPixels i
 BL.appendFile fileName content