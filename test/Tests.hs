{-# LANGUAGE CPP, OverloadedStrings, RecordWildCards, LambdaCase, OverloadedLists, TypeApplications #-}
module Tests where


#if __GLASGOW_HASKELL__ < 710
import Control.Applicative
import Data.Monoid (mappend)
#endif
import qualified Control.Concurrent.Async as Async
import Control.Exception (try)
import Control.Concurrent
import Control.Monad
import Control.Monad.Trans
import Control.Monad.Trans.Except
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as Char8
import Data.Either (isRight)
import qualified Data.List as L
import qualified Data.List.NonEmpty as NE
import Data.Time
import Data.Time.Clock.POSIX
import qualified Test.Framework as Test (Test)
import qualified Test.Framework.Providers.HUnit as Test (testCase)
import qualified Test.HUnit as HUnit
import qualified Test.HUnit.Lang as HUnit.Lang
import Network.Socket (PortNumber)

import Database.Redis
import Data.Either (fromRight)

------------------------------------------------------------------------------
-- helpers
--
type Test = Connection -> Test.Test

testCase :: String -> Redis () -> Test
testCase name r conn = Test.testCase name $ do
    withTimeLimit 0.5 $ runRedis conn $ flushdb >>=? Ok >> r
  where
    withTimeLimit limit act = do
        start <- getCurrentTime
        _ <- act
        deltaT <-fmap (`diffUTCTime` start) getCurrentTime
        when (deltaT > limit) $
            putStrLn $ name ++ ": " ++ show deltaT

(>>=?) :: (Eq a, Show a) => Redis (Either Reply a) -> a -> Redis ()
redis >>=? expected = redis >>@? (expected HUnit.@=?)

(>>@?) :: (Eq a, Show a) => Redis (Either Reply a) -> (a -> HUnit.Assertion) -> Redis ()
redis >>@? predicate = do
    a <- redis
    liftIO $ case a of
        Left reply -> HUnit.assertFailure $ "Redis error: " ++ show reply
        Right actual -> predicate actual

(<|?>) :: HUnit.Assertion -> HUnit.Assertion -> HUnit.Assertion
a <|?> b = do
    resultA <- HUnit.Lang.performTestCase a
    case resultA of
        HUnit.Lang.Success        -> a
        HUnit.Lang.Failure _ errA -> tryB errA
        HUnit.Lang.Error   _ errA -> tryB errA
        where tryB errA = do
                        resultB <- HUnit.Lang.performTestCase b
                        case resultB of
                            HUnit.Lang.Success        -> b
                            HUnit.Lang.Failure _ errB -> concatErrors errA errB
                            HUnit.Lang.Error   _ errB -> concatErrors errA errB
              concatErrors errA errB = HUnit.Lang.assertFailure ("{" ++ errA ++ "\nOR\n" ++ errB ++ "\n}: Failed")


assert :: Bool -> Redis ()
assert = liftIO . HUnit.assert

isUnknownCommandReply :: Reply -> Bool
isUnknownCommandReply (Error message) = "unknown command" `BS.isInfixOf` message
isUnknownCommandReply _ = False

isHotkeysInactiveReply :: Reply -> Bool
isHotkeysInactiveReply (Error message) =
    "not currently active" `BS.isInfixOf` message || "tracking is not active" `BS.isInfixOf` message
isHotkeysInactiveReply (Bulk Nothing) = True
isHotkeysInactiveReply _ = False

------------------------------------------------------------------------------
-- Miscellaneous
--
testsMisc :: [Test]
testsMisc =
    [ testConstantSpacePipelining, testForceErrorReply, testPipelining
    , testEvalReplies, testGeo
    ]

testConstantSpacePipelining :: Test
testConstantSpacePipelining = testCase "constant-space pipelining" $ do
    -- This testcase should not exceed the maximum heap size, as set in
    -- the run-test.sh script.
    replicateM_ 100000 ping
    -- If the program didn't crash, pipelining takes constant memory.
    assert True

testForceErrorReply :: Test
testForceErrorReply = testCase "force error reply" $ do
    set "key" "value" >>= \case
      Left _ -> error "impossible"
      _ -> return ()
    -- key is not a hash -> wrong kind of value
    reply <- hkeys "key"
    assert $ case reply of
        Left (Error _) -> True
        _              -> False

testPipelining :: Test
testPipelining = testCase "pipelining" $ do
    let n = 100
    tPipe <- deltaT $ do
        pongs <- replicateM n ping
        assert $ pongs == replicate n (Right Pong)

    tNoPipe <- deltaT $ replicateM_ n (ping >>=? Pong)
    -- pipelining should at least be twice as fast.
    assert $ tNoPipe / tPipe > 2
  where
    deltaT redis = do
        start <- liftIO $ getCurrentTime
        _ <- redis
        liftIO $ fmap (`diffUTCTime` start) getCurrentTime

testEvalReplies :: Test
testEvalReplies conn = testCase "eval unused replies" go conn
  where
    go = do
      _ <- liftIO $ runRedis conn $ set "key-12" "value"
      result <- liftIO $ do
         threadDelay $ 10 ^ (5 :: Int)
         mvar <- newEmptyMVar
         _ <-
           (Async.wait =<< Async.async (runRedis conn (get "key-12"))) >>= putMVar mvar
         takeMVar mvar
      pure result >>=? Just "value"

testGeo :: Test
testGeo = testCase "geo" $ do
    geoadd "{geo}cities" [(13.361389, 38.115556, "Palermo"), (15.087269, 37.502669, "Catania")] >>=? 2
    geoaddOpts "{geo}cities"
        [(13.361389, 38.115556, "Palermo"), (12.496366, 41.902782, "Rome")]
        defaultGeoAddOpts { geoAddCondition = Just Nx, geoAddChange = True } >>=? 1
    geodist "{geo}cities" "Palermo" "Rome" (Just GeoKilometers) >>@? \actual ->
        case actual of
            Just dist -> HUnit.assertBool "Rome should have been inserted by GEOADD NX" (dist > 400)
            Nothing -> HUnit.assertFailure "GEODIST Palermo Rome returned Nothing"
    geoaddOpts "{geo}cities"
        [(9.1900, 45.4642, "Milan")]
        defaultGeoAddOpts { geoAddCondition = Just Xx } >>=? 0

    geodist "{geo}cities" "Palermo" "Catania" Nothing >>@? \actual ->
        case actual of
            Just dist -> HUnit.assertBool "unexpected GEODIST distance in meters" (abs (dist - 166274.1516) < 1000)
            Nothing -> HUnit.assertFailure "GEODIST returned Nothing"

    geopos "{geo}cities" ["Palermo", "Catania"] >>@? \positions ->
        case positions of
            [Just palermo, Just catania] -> do
                assertApprox "Palermo longitude" 13.361389 (geoLongitude palermo)
                assertApprox "Palermo latitude" 38.115556 (geoLatitude palermo)
                assertApprox "Catania longitude" 15.087269 (geoLongitude catania)
                assertApprox "Catania latitude" 37.502669 (geoLatitude catania)
            _ -> HUnit.assertFailure $ "Unexpected GEOPOS response: " ++ show positions

    let searchOpts = defaultGeoSearchOpts
            { geoSearchWithDist = True
            , geoSearchOrder = Just GeoAsc
            }

    geoSearch "{geo}cities" (GeoSearchFromMember "Palermo") (GeoSearchByRadius 200 GeoKilometers) searchOpts >>@? \locations ->
        case locations of
            [palermo, catania] -> do
                HUnit.assertEqual "GEOSEARCH center member" "Palermo" (geoLocationMember palermo)
                HUnit.assertBool "GEOSEARCH distance should be zero for center member" (maybe False (< 0.001) (geoLocationDist palermo))
                HUnit.assertEqual "GEOSEARCH second member" "Catania" (geoLocationMember catania)
            _ -> HUnit.assertFailure $ "Unexpected GEOSEARCH response: " ++ show locations

    geoSearchStore "{geo}near" "{geo}cities" (GeoSearchFromLonLat 15 37) (GeoSearchByRadius 200 GeoKilometers)
        (defaultGeoSearchStoreOpts { geoSearchStoreStoredist = True }) >>=? 2

    zrangeWithscores "{geo}near" 0 (-1) >>@? \members ->
        case members of
            [(firstCity, firstDistance), (secondCity, secondDistance)] -> do
                HUnit.assertEqual "closest stored city" "Catania" firstCity
                HUnit.assertEqual "second stored city" "Palermo" secondCity
                HUnit.assertBool "stored distances should be increasing" (firstDistance < secondDistance)
            _ -> HUnit.assertFailure $ "Unexpected GEOSEARCHSTORE response: " ++ show members
  where
    assertApprox label expected actual =
        HUnit.assertBool label (abs (expected - actual) < 0.0001)

------------------------------------------------------------------------------
-- Keys
--
testKeys :: Test
testKeys = testCase "keys" $ do
    set "{same}key" "value"     >>=? Ok
    get "{same}key"             >>=? Just "value"
    exists "{same}key"          >>=? True
    expire "{same}key" 1        >>=? True
    pexpire "{same}key" 1000    >>=? True
    ttl "{same}key" >>= \case
      Left _ -> error "error"
      Right t -> do
        assert $ elem @[] t [0..1]
        pttl "{same}key" >>= \case
          Left _ -> error "error"
          Right pt -> do
            assert $ elem @[] pt [990..1000]
            persist "{same}key"         >>=? True
            dump "{same}key" >>= \case
              Left _ -> error "impossible"
              Right s -> do
                restore "{same}key'" 0 s          >>=? Ok
                rename "{same}key" "{same}key'"   >>=? Ok
                renamenx "{same}key'" "{same}key" >>=? True
                del (NE.fromList ["{same}key"])   >>=? 1

testCopy :: Test
testCopy = testCase "copy" $ do
    set "dolly" "sheep" >>=? Ok
    copy "dolly" "clone" >>=? True
    get "clone" >>=? Just "sheep"
    copy "dolly" "clone" >>=? False
    copyOpts "dolly" "clone" defaultCopyOpts { copyReplace = True } >>=? True

testKeysNoncluster :: Test
testKeysNoncluster = testCase "keysNoncluster" $ do
    set "key" "value"     >>=? Ok
    keys "*"              >>=? ["key"]
    randomkey             >>=? Just "key"
    move "key" 13         >>=? True
    select 13             >>=? Ok
    get "key"             >>=? Just "value"
    select 0              >>=? Ok

testExpireAt :: Test
testExpireAt = testCase "expireat" $ do
    set "key" "value"             >>=? Ok
    t <- ceiling . utcTimeToPOSIXSeconds <$> liftIO getCurrentTime
    let expiry = t+1
    expireat "key" expiry         >>=? True
    pexpireat "key" (expiry*1000) >>=? True

testSort :: Test
testSort = testCase "sort" $ do
    lpush "ids"     ["1","2","3"]                >>=? 3
    sort "ids" defaultSortOpts                   >>=? ["1","2","3"]
    sortStore "ids" "anotherKey" defaultSortOpts >>=? 3
    mset
         [("weight_1","1")
         ,("weight_2","2")
         ,("weight_3","3")
         ,("object_1","foo")
         ,("object_2","bar")
         ,("object_3","baz")
         ] >>= \case
      Left _ -> error "error"
      _ -> return ()
    let opts = defaultSortOpts { sortOrder = Desc, sortAlpha = True
                               , sortLimit = (1,2)
                               , sortBy    = Just "weight_*"
                               , sortGet   = ["#", "object_*"] }
    sort "ids" opts >>=? ["2", "bar", "1", "foo"]


testGetType :: Test
testGetType = testCase "getType" $ do
    getType "key"     >>=? None
    forM_ @[] ts $ \(setKey, typ) -> do
        setKey
        getType "key" >>=? typ
        del (NE.fromList ["key"])   >>=? 1
  where
    ts = [ (set "key" "value"                         >>=? Ok,   String)
         , (hset "key" [("field"::ByteString, "value"::ByteString)] >>=? 1,    Hash)
         , (lpush "key" ["value"]                     >>=? 1,    List)
         , (sadd "key" ["member"]                     >>=? 1,    Set)
         , (zadd "key" [(42,"member"),(12.3,"value")] >>=? 2,    ZSet)
         ]

testObject :: Test
testObject = testCase "object" $ do
    set "key" "value"    >>=? Ok
    objectRefcount "key" >>=? 1
    objectEncoding "key" >>= \case
       Left _ -> error "error"
       _ -> return ()
    objectIdletime "key" >>=? 0
    return ()

------------------------------------------------------------------------------
-- Strings
--
testsStrings :: [Test]
testsStrings = [testStrings, testStringCommands6, testBitops]

testStrings :: Test
testStrings = testCase "strings" $ do
    setnx "key" "value"                           >>=? True
    getset "key" "hello"                          >>=? Just "value"
    append "key" "world"                          >>=? 10
    strlen "key"                                  >>=? 10
    setrange "key" 0 "hello"                      >>=? 10
    getrange "key" 0 4                            >>=? "hello"
    substr "key" 0 4                              >>=? "hello"
    mset [("{same}k1","v1"), ("{same}k2","v2")]   >>=? Ok
    msetnx [("{same}k1","v1"), ("{same}k2","v2")] >>=? False
    mget ["key"]                                  >>=? [Just "helloworld"]
    setex "key" 1 "42"                            >>=? Ok
    psetex "key" 1000 "42"                        >>=? Ok
    decr "key"                                    >>=? 41
    decrby "key" 1                                >>=? 40
    incr "key"                                    >>=? 41
    incrby "key" 1                                >>=? 42
    incrbyfloat "key" 1                           >>=? 43
    del (NE.fromList ["key"])                     >>=? 1
    setbit "key" 42 "1"                           >>=? 0
    getbit "key" 42                               >>=? 1
    bitcount "key"                                >>=? 1
    bitcountRange "key" 0 (-1)                    >>=? 1

testStringCommands6 :: Test
testStringCommands6 = testCase "strings redis 6" $ do
    set "mykey" "Hello" >>=? Ok
    getdel "mykey" >>=? Just "Hello"
    get "mykey" >>=? Nothing
    set "mykey" "Hello" >>=? Ok
    getexOpts "mykey" defaultGetExOpts { getExSeconds = Just 10 } >>=? Just "Hello"
    ttl "mykey" >>@? \value ->
        HUnit.assertBool "GETEX should set ttl" (value >= 0 && value <= 10)

testStringCommands84 :: Test
testStringCommands84 = testCase "strings redis 8.4" $ do
    set "digest-key" "Hello world" >>=? Ok
    digest "digest-key" >>=? Just "b6acb9d84a38ff74"
    delexWhen "digest-key" (DelexIfEq "Goodbye") >>=? False
    get "digest-key" >>=? Just "Hello world"
    digest "digest-key" >>= \case
        Left reply -> liftIO $ HUnit.assertFailure $ "Redis error: " ++ show reply
        Right (Just digestValue) -> do
            delexWhen "digest-key" (DelexIfDigestEq digestValue) >>=? True
            get "digest-key" >>=? Nothing
        Right Nothing -> liftIO $ HUnit.assertFailure "DIGEST should return a digest for an existing string key"

    msetexOpts (("k1", "v1") NE.:| [("k2", "v2")]) defaultSetOpts { setSeconds = Just 60 } >>=? True
    mget ["k1", "k2"] >>=? [Just "v1", Just "v2"]
    ttl "k1" >>@? \value ->
        HUnit.assertBool "MSETEX should set ttl" (value >= 0 && value <= 60)

    msetexOpts (("k1", "new-v1") NE.:| [("k3", "v3")]) defaultSetOpts { setCondition = Just Nx } >>=? False
    get "k1" >>=? Just "v1"
    get "k3" >>=? Nothing

    msetexOpts (("k1", "new-v1") NE.:| [("k2", "new-v2")]) defaultSetOpts { setCondition = Just Xx } >>=? True
    mget ["k1", "k2"] >>=? [Just "new-v1", Just "new-v2"]

testBitops :: Test
testBitops = testCase "bitops" $ do
    set "{same}k1" "a"                           >>=? Ok
    set "{same}k2" "b"                           >>=? Ok
    bitopAnd "{same}k3" ["{same}k1", "{same}k2"] >>=? 1
    bitopOr "{same}k3" ["{same}k1", "{same}k2"]  >>=? 1
    bitopXor "{same}k3" ["{same}k1", "{same}k2"] >>=? 1
    bitopNot "{same}k3" "{same}k1"               >>=? 1

------------------------------------------------------------------------------
-- Hashes
--
testHashes :: Test
testHashes = testCase "hashes" $ do
    hset "key" [("field"::ByteString, "another"::ByteString)] >>=? 1
    hset "key" [("field"::ByteString, "another"::ByteString)] >>=? 0
    hset "key" [("field"::ByteString, "value"::ByteString)]   >>=? 0
    hsetnx "key" "field" "value" >>=? False
    hexists "key" "field"        >>=? True
    hlen "key"                   >>=? 1
    hget "key" "field"           >>=? Just "value"
    hmget "key" ["field", "-"]   >>=? [Just "value", Nothing]
    hgetall "key"                >>=? [("field","value")]
    hkeys "key"                  >>=? ["field"]
    hvals "key"                  >>=? ["value"]
    hdel "key" ["field"]         >>=? 1
    hmset "key" [("field","40")] >>=? Ok
    hincrby "key" "field" 2      >>=? 42
    hincrbyfloat "key" "field" 2 >>=? 44
    hset "coin" [("heads","obverse"),("tails","reverse"),("edge","null")] >>=? 3
    hrandfield "coin" >>@? \field ->
        HUnit.assertBool "HRANDFIELD should return an existing field" (field `elem` ([Just "heads", Just "tails", Just "edge"] :: [Maybe ByteString]))
    hrandfieldCount "coin" 2 >>@? \fields -> do
        HUnit.assertEqual "HRANDFIELD count" 2 (length fields)
        HUnit.assertBool "HRANDFIELD count should return distinct fields" (fields == L.nub fields)
        HUnit.assertBool "HRANDFIELD count should return existing fields" (all (`elem` (["heads", "tails", "edge"] :: [ByteString])) fields)
    hrandfieldCountWithValues "coin" 2 >>@? \fields -> do
        HUnit.assertEqual "HRANDFIELD WITHVALUES count" 2 (length fields)
        HUnit.assertBool "HRANDFIELD WITHVALUES should return existing field/value pairs" $
            all (`elem` ([("heads", "obverse"), ("tails", "reverse"), ("edge", "null")] :: [(ByteString, ByteString)])) fields

testHashes8 :: Test
testHashes8 = testCase "hashes redis 8" $ do
    hsetexOpts "myhash" (("field1", "Hello") NE.:| [("field2", "World")])
        defaultHSetExOpts { hSetExSeconds = Just 60 }
        >>=? True
    httl "myhash" ["field1"] >>@? \case
        (HashFieldExpirationInfo value:_) ->
           HUnit.assertBool ("HSETEX should set ttl: " <> show value) (value >= 0 && value <= 60)
        x -> HUnit.assertFailure $ "HTTL should return field expiration info for field1" <> show x

    hgetexOpts "myhash" ("field1" NE.:| ["field2", "missing"])
        defaultHGetExOpts { hGetExPersist = True }
        >>=? [Just "Hello", Just "World", Nothing]
    ttl "myhash" >>=? (-1)

    hgetdel "myhash" ("field1" NE.:| ["field2", "missing"])
        >>=? [Just "Hello", Just "World", Nothing]
    hgetall "myhash" >>=? []

    hsetexOpts "myhash" (("field1", "Hello") NE.:| [])
        defaultHSetExOpts { hSetExCondition = Just HSetExFnx }
        >>=? True
    hsetexOpts "myhash" (("field1", "World") NE.:| [])
        defaultHSetExOpts { hSetExCondition = Just HSetExFnx }
        >>=? False
    hsetexOpts "myhash" (("field1", "World") NE.:| [])
        defaultHSetExOpts { hSetExCondition = Just HSetExFxx }
        >>=? True
    hget "myhash" "field1" >>=? Just "World"

------------------------------------------------------------------------------
-- Lists
--
testsLists :: [Test]
testsLists =
    [testLists, testListCommands6, testBpop]

testLists :: Test
testLists = testCase "lists" $ do
    lpushx "notAKey" ["-" :: ByteString] >>=? 0
    rpushx "notAKey" ["-" :: ByteString] >>=? 0
    lpush "key" ["value"]         >>=? 1
    lpop "key"                    >>=? Just "value"
    rpush "key" ["value"]         >>=? 1
    rpop "key"                    >>=? Just "value"
    rpush "key" ["v2"]            >>=? 1
    linsertBefore "key" "v2" "v1" >>=? 2
    linsertAfter "key" "v2" "v3"  >>=? 3
    lindex "key" 0                >>=? Just "v1"
    lrange "key" 0 (-1)           >>=? ["v1", "v2", "v3"]
    lset "key" 1 "v2"             >>=? Ok
    lrem "key" 0 "v2"             >>=? 1
    llen "key"                    >>=? 2
    ltrim "key" 0 1               >>=? Ok
    del ("key" NE.:| [])
    -- keys are pushed sequentially so this will result in a list with value1, value2, value3
    lpush "key" ["value3", "value2", "value1"] >>=? 3
    lpopCount "key" 2 >>=? ["value1", "value2"]
    lpush "key" ["value2", "value1"] >>=? 3
    rpopCount "key" 2 >>=? ["value3", "value2"]
    del ("key" NE.:| [])
    lpush "key" ["value3", "value2", "value1"] >>=? 3
    lpopCount "key" 4 >>=? ["value1", "value2", "value3"]
    del ("key" NE.:| [])
    return ()

testListCommands6 :: Test
testListCommands6 = testCase "lists redis 6" $ do
    rpush "mylist" ["a", "b", "c", "d", "1", "2", "3", "4", "3", "3", "3"] >>=? 11
    lpos "mylist" "3" >>=? Just 6
    lposCount "mylist" "3" 0 >>=? [6, 8, 9, 10]
    lposOpts "mylist" "3" defaultLPosOpts { lposRank = Just 2 } >>=? Just 8

    rpush "{same}src" ["one", "two", "three"] >>=? 3
    lmove "{same}src" "{same}dst" ListLeft ListRight >>=? Just "one"
    lrange "{same}src" 0 (-1) >>=? ["two", "three"]
    lrange "{same}dst" 0 (-1) >>=? ["one"]

    rpush "{same}src2" ["one", "two", "three"] >>=? 3
    blmove "{same}src2" "{same}dst2" ListRight ListLeft 1 >>=? Just "three"
    lrange "{same}src2" 0 (-1) >>=? ["one", "two"]
    lrange "{same}dst2" 0 (-1) >>=? ["three"]

testBpop :: Test
testBpop = testCase "blocking push/pop" $ do
    lpush "{same}key" ["v3","v2","v1"] >>=? 3
    blpop ["{same}key"] 1              >>=? Just ("{same}key","v1")
    brpop ["{same}key"] 1              >>=? Just ("{same}key","v3")
    rpush "{same}k1" ["v1","v2"]       >>=? 2
    brpoplpush "{same}k1" "{same}k2" 1 >>=? Just "v2"
    rpoplpush "{same}k1" "{same}k2"    >>=? Just "v1"

------------------------------------------------------------------------------
-- Sets
--
testsSets :: [Test]
testsSets = [testSets, testSMIsMember, testSetAlgebra]

testSets :: Test
testSets = testCase "sets" $ do
    sadd "set" (NE.fromList  ["member"]) >>=? 1
    sismember "set" "member"    >>=? True
    scard "set"                 >>=? 1
    smembers "set"              >>=? ["member"]
    srandmember "set"           >>=? Just "member"
    spop "set"                  >>=? Just "member"
    srem "set" (NE.fromList ["member"]) >>=? 0
    smove "{same}set" "{same}set'" "member" >>=? False
    _ <- sadd "set" (NE.fromList ["member1", "member2"])
    (fmap L.sort <$> spopN "set" 2) >>=? ["member1", "member2"]
    _ <- sadd "set" (NE.fromList ["member1", "member2"])
    (fmap L.sort <$> srandmemberN "set" 2) >>=? ["member1", "member2"]

testSMIsMember :: Test
testSMIsMember = testCase "smismember" $ do
    sadd "myset" (NE.fromList ["one"]) >>=? 1
    smismember "myset" ("one" NE.:| ["notamember"]) >>=? [True, False]

testSetAlgebra :: Test
testSetAlgebra = testCase "set algebra" $ do
    sadd "{same}s1" (NE.fromList ["member"])        >>=? 1
    sdiff ["{same}s1", "{same}s2"]                  >>=? ["member"]
    sunion ["{same}s1", "{same}s2"]                 >>=? ["member"]
    sinter ["{same}s1", "{same}s2"]                 >>=? []
    sdiffstore "{same}s3" ["{same}s1", "{same}s2"]  >>=? 1
    sunionstore "{same}s3" ["{same}s1", "{same}s2"] >>=? 1
    sinterstore "{same}s3" ["{same}s1", "{same}s2"] >>=? 0

------------------------------------------------------------------------------
-- Sorted Sets
--
testsZSets :: [Test]
testsZSets = [testZSets, testSortedSetCommands6, testZStore]

testZSets :: Test
testZSets = testCase "sorted sets" $ do
    zadd "key" [(1,"v1"),(2,"v2"),(40,"v3")]          >>=? 3
    zcard "key"                                       >>=? 3
    zscore "key" "v3"                                 >>=? Just 40
    zincrby "key" 2 "v3"                              >>=? 42

    zrank "key" "v1"                                  >>=? Just 0
    zrevrank "key" "v1"                               >>=? Just 2
    zcount "key" 10 100                               >>=? 1

    zrange "key" 0 1                                  >>=? ["v1","v2"]
    zrevrange "key" 0 1                               >>=? ["v3","v2"]
    zrangeWithscores "key" 0 1                        >>=? [("v1",1),("v2",2)]
    zrevrangeWithscores "key" 0 1                     >>=? [("v3",42),("v2",2)]
    zrangebyscore "key" 0.5 1.5                       >>=? ["v1"]
    zrangebyscoreWithscores "key" 0.5 1.5             >>=? [("v1",1)]
    zrangebyscoreWithscores "key" (-inf) inf          >>=? [("v1",1.0),("v2",2.0),("v3",42.0)]
    zrangebyscoreLimit "key" 0.5 2.5 0 1              >>=? ["v1"]
    zrangebyscoreWithscoresLimit "key" 0.5 2.5 0 1    >>=? [("v1",1)]
    zrevrangebyscore "key" 1.5 0.5                    >>=? ["v1"]
    zrevrangebyscoreWithscores "key" 1.5 0.5          >>=? [("v1",1)]
    zrevrangebyscoreLimit "key" 2.5 0.5 0 1           >>=? ["v2"]
    zrevrangebyscoreWithscoresLimit "key" 2.5 0.5 0 1 >>=? [("v2",2)]

    zrem "key" (NE.fromList ["v2"])                   >>=? 1
    zremrangebyscore "key" 10 100                     >>=? 1
    zremrangebyrank "key" 0 0                         >>=? 1

testSortedSetCommands6 :: Test
testSortedSetCommands6 = testCase "sorted sets redis 6" $ do
    zadd "{same}zset1" [(1, "one"), (2, "two"), (3, "three")] >>=? 3
    zadd "{same}zset2" [(1, "one"), (2, "two")] >>=? 2

    zdiff ("{same}zset1" NE.:| ["{same}zset2"]) >>=? ["three"]
    zdiffWithscores ("{same}zset1" NE.:| ["{same}zset2"]) >>=? [("three", 3)]
    zdiffstore "{same}out" ("{same}zset1" NE.:| ["{same}zset2"]) >>=? 1
    zrangeWithscores "{same}out" 0 (-1) >>=? [("three", 3)]

    zinter ("{same}zset1" NE.:| ["{same}zset2"]) >>=? ["one", "two"]
    zinterWithscores ("{same}zset1" NE.:| ["{same}zset2"]) >>=? [("one", 2), ("two", 4)]
    zinterWithscoresOpts ("{same}zset1" NE.:| ["{same}zset2"])
        defaultZAggregateOpts { zAggregateWeights = [2, 3], zAggregateAggregate = Max }
        >>=? [("one", 3), ("two", 6)]

    zunion ("{same}zset1" NE.:| ["{same}zset2"]) >>=? ["one", "three", "two"]
    zunionWithscores ("{same}zset1" NE.:| ["{same}zset2"]) >>=? [("one", 2), ("three", 3), ("two", 4)]
    zmscore "{same}zset1" ("one" NE.:| ["notamember"]) >>=? [Just 1, Nothing]

    zrandmember "{same}zset1" >>@? \member ->
        HUnit.assertBool "ZRANDMEMBER should return an existing member" (member `elem` ([Just "one", Just "two", Just "three"] :: [Maybe ByteString]))
    zrandmemberN "{same}zset1" 2 >>@? \members -> do
        HUnit.assertEqual "ZRANDMEMBER count" 2 (length members)
        HUnit.assertBool "ZRANDMEMBER count should return existing members" (all (`elem` (["one", "two", "three"] :: [ByteString])) members)
    zrandmemberWithscores "{same}zset1" 2 >>@? \members -> do
        HUnit.assertEqual "ZRANDMEMBER WITHSCORES count" 2 (length members)
        HUnit.assertBool "ZRANDMEMBER WITHSCORES should return valid pairs" $
            all (`elem` ([("one", 1), ("two", 2), ("three", 3)] :: [(ByteString, Double)])) members

    zrangestore "{same}newzset" "{same}zset1" 2 (-1) >>=? 1
    zrange "{same}newzset" 0 (-1) >>=? ["three"]

--  testZSets7 :: Test
--  testZSets7 = testCase "sorted sets: redis 7" $ do
--      zadd "key" [(2,"v1"),(0,"v2"),(40,"v3")]          >>=? 3
--      zrankWithScore "key" "v1"                         >>=? Just  (1, 2)

testZStore :: Test
testZStore = testCase "zunionstore/zinterstore" $ do
    zadd "{same}k1" [(1, "v1"), (2, "v2")] >>= \case
      Left _ -> error "error"
      _ -> return ()
    zadd "{same}k2" [(2, "v2"), (3, "v3")] >>= \case
      Left _ -> error "error"
      _ -> return ()
    zinterstore "{same}newkey" ["{same}k1","{same}k2"] Sum                >>=? 1
    zinterstoreWeights "{same}newkey" [("{same}k1",1),("{same}k2",2)] Max >>=? 1
    zunionstore "{same}newkey" ["{same}k1","{same}k2"] Sum                >>=? 3
    zunionstoreWeights "{same}newkey" [("{same}k1",1),("{same}k2",2)] Min >>=? 3

------------------------------------------------------------------------------
-- HyperLogLog
--

testHyperLogLog :: Test
testHyperLogLog = testCase "hyperloglog" $ do
  -- test creation
  pfadd "hll1" ["a"] >>= \case
      Left _ -> error "error"
      _ -> return ()
  pfcount ["hll1"] >>=? 1
  -- test cardinality
  pfadd "hll1" ["a"] >>= \case
      Left _ -> error "error"
      _ -> return ()
  pfcount ["hll1"] >>=? 1
  pfadd "hll1" ["b", "c", "foo", "bar"] >>= \case
      Left _ -> error "error"
      _ -> return ()
  pfcount ["hll1"] >>=? 5
  -- test merge
  pfadd "{same}hll2" ["1", "2", "3"] >>= \case
      Left _ -> error "error"
      _ -> return ()
  pfadd "{same}hll3" ["4", "5", "6"] >>= \case
      Left _ -> error "error"
      _ -> return ()
  pfmerge "{same}hll4" ["{same}hll2", "{same}hll3"] >>= \case
      Left _ -> error "error"
      _ -> return ()
  pfcount ["{same}hll4"] >>=? 6
  -- test union cardinality
  pfcount ["{same}hll2", "{same}hll3"] >>=? 6

------------------------------------------------------------------------------
-- Bloom Filters
--
testBloomFilter :: Test
testBloomFilter = testCase "bloom filter" $ do
    liftIO $ putStrLn "Testing bloom filter with default parameters..."
    bfadd "bf1" "observation1" >>=? True
    liftIO $ putStrLn "Testing bloom filter info commands..."
    bfinfoSize "bf1" >>=? [240]
    liftIO $ putStrLn "Testing bloom filter info commands with error handling..."
    Right [infoSize] <- bfinfoSize "bf1"
    liftIO $ putStrLn $ "Bloom filter info: " ++ show infoSize
    bfinfo "bf1" >>=? BFInfo
        { bfInfoCapacity = 100
        , bfInfoSize = infoSize
        , bfInfoFilters = 1
        , bfInfoItems = 1
        , bfInfoExpansion = 2
        }
    bfinfoCapacity "bf1" >>=? [100]
    bfinfoFilters "bf1" >>=? [1]
    bfinfoItems "bf1" >>=? [1]
    bfinfoExpansion "bf1" >>=? [Just 2]
    bfcard "bf1" >>=? 1
    bfcard "bf_new" >>=? 0


    liftIO $ putStrLn "Testing bloom filter with custom parameters..."

    bfreserve "bf" 0.01 1000 >>=? Ok
    bfadd "bf" "item1" >>=? True
    bfexists "bf" "item1" >>=? True
    bfexists "bf" "item2" >>=? False

    liftIO $ putStrLn "Testing bloom filter multi-item commands..."

    bfmadd "bfm" ("item1" NE.:| ["item2", "item2"]) >>=? [True, True, False]
    bfmexists "bfm" ("item1" NE.:| ["item2", "item3"]) >>=? [True, True, False]

    liftIO $ putStrLn "Testing bloom filter insert commands with custom parameters..."

    bfinsert "bfi" ("item1" NE.:| ["item2"]) >>=? [True, True]
    bfinsertOpts "bf_insert" ("item1" NE.:| ["item2"]) defaultBFInsertOpts
        { bfInsertCapacity = Just 1000
        , bfInsertError = Just 0.01
        , bfInsertExpansion = Just 3
        , bfInsertNonScaling = True
        } >>=? [True, True]


    bfinfoCapacity "bf_insert" >>=? [1000]
    bfinfoExpansion "bf_insert" >>=? [Nothing]

    bfinsertOpts "bf_insert1" ("item1" NE.:| ["item2"]) defaultBFInsertOpts
        { bfInsertCapacity = Just 1000
        , bfInsertError = Just 0.01
        , bfInsertExpansion = Just 4
        , bfInsertNonScaling = False
        } >>=? [True, True]
    bfinfoExpansion "bf_insert1" >>=? [Just 4]


    bfreserveOpts "bf_exp" 0.01 1000 defaultBFReserveOpts
        { bfReserveExpansion = Just 2
        } >>=? Ok
    bfinfoExpansion "bf_exp" >>=? [Just 2]


    bfreserve "bfdump" 0.1 10 >>=? Ok
    bfadd "bfdump" "item1" >>=? True

-- Count-Min Sketches
--
testCountMinSketch :: Test
testCountMinSketch = testCase "count-min sketch" $ do
    cmsinitbydim "cms1" 20 5 >>=? Ok
    cmsinfo "cms1" >>=? CMSInfo
        { cmsInfoWidth = 20
        , cmsInfoDepth = 5
        , cmsInfoCount = 0
        }

    cmsincrby "cms1" (("foo", 2) NE.:| [("bar", 3), ("foo", 4)]) >>=? [2, 3, 6]
    cmsquery "cms1" ("foo" NE.:| ["bar", "baz"]) >>=? [6, 3, 0]
    cmsinfo "cms1" >>=? CMSInfo
        { cmsInfoWidth = 20
        , cmsInfoDepth = 5
        , cmsInfoCount = 9
        }

    cmsinitbyprob "cms2" 0.001 0.99 >>=? Ok
    cmsquery "cms2" ("foo" NE.:| ["bar"]) >>=? [0, 0]
    cmsincrby "cms2" (("foo", 7) NE.:| [("bar", 1)]) >>=? [7, 1]
    cmsinfo "cms2" >>@? \CMSInfo{..} -> do
        HUnit.assertBool "cms2 width should be positive" (cmsInfoWidth > 0)
        HUnit.assertBool "cms2 depth should be positive" (cmsInfoDepth > 0)
        8 HUnit.@=? cmsInfoCount

    cmsinitbydim "cms3" 20 5 >>=? Ok
    cmsincrby "cms3" (("foo", 7) NE.:| [("bar", 1)]) >>=? [7, 1]

    cmsinitbydim "cms_merged" 20 5 >>=? Ok
    cmsmerge "cms_merged" ("cms1" NE.:| ["cms3"]) >>=? Ok
    cmsquery "cms_merged" ("foo" NE.:| ["bar", "baz"]) >>=? [13, 4, 0]

    cmsinitbydim "cms_weighted" 20 5 >>=? Ok
    cmsmergeWeighted "cms_weighted" (("cms1", 1) NE.:| [("cms3", 2)]) >>=? Ok
    cmsquery "cms_weighted" ("foo" NE.:| ["bar", "baz"]) >>=? [20, 5, 0]

-- Top-K
--
testTopk :: Test
testTopk = testCase "topk" $ do
    topkReserve "topk1" 3 50 5 0.9 >>=? Ok
    topkInfo "topk1" >>=? TopkInfo
        { topkInfoK = 3
        , topkInfoWidth = 50
        , topkInfoDepth = 5
        , topkInfoDecay = 0.9
        }

    topkAdd "topk1" ("foo" NE.:| ["bar", "baz"]) >>=? [Nothing, Nothing, Nothing]
    topkQuery "topk1" ("foo" NE.:| ["bar", "missing"]) >>=? [True, True, False]
    topkCount "topk1" ("foo" NE.:| ["bar", "missing"]) >>@? \counts ->
        case counts of
            [fooCount, barCount, 0] -> do
                HUnit.assertBool "TOPK.COUNT foo should be positive" (fooCount > 0)
                HUnit.assertBool "TOPK.COUNT bar should be positive" (barCount > 0)
            _ -> HUnit.assertFailure $ "Unexpected TOPK.COUNT response: " ++ show counts

    topkIncrby "topk1" (("foo", 10) NE.:| [("baz", 3), ("qux", 1)]) >>@? \results ->
        HUnit.assertEqual "TOPK.INCRBY result length" 3 (length results)

    topkList "topk1" >>@? \items -> do
        HUnit.assertEqual "TOPK.LIST length" 3 (length items)
        HUnit.assertBool "TOPK.LIST should include foo" ("foo" `elem` items)

    topkListWithCount "topk1" >>@? \itemsWithCount -> do
        HUnit.assertEqual "TOPK.LIST WITHCOUNT length" 3 (length itemsWithCount)
        let itemKeys = map fst itemsWithCount
        HUnit.assertBool "TOPK.LIST WITHCOUNT should include foo" ("foo" `elem` itemKeys)
        HUnit.assertBool "TOPK.LIST WITHCOUNT counts should be positive" (all ((> 0) . snd) itemsWithCount)

-- T-Digest
--
testTdigest :: Test
testTdigest = testCase "tdigest" $ do
    tdigestCreate "td1" >>=? Ok
    tdigestAdd "td1" (1 NE.:| [2, 3, 4, 5]) >>=? Ok

    tdigestMin "td1" >>=? 1
    tdigestMax "td1" >>=? 5
    tdigestByrank "td1" (0 NE.:| [2, 4]) >>@? \values ->
        case values of
            [v0, v2, v4] -> do
                HUnit.assertEqual "TDIGEST.BYRANK 0" 1 v0
                HUnit.assertBool "TDIGEST.BYRANK 2 should be within range" (v2 >= 2 && v2 <= 4)
                HUnit.assertEqual "TDIGEST.BYRANK 4" 5 v4
            _ -> HUnit.assertFailure $ "Unexpected TDIGEST.BYRANK response: " ++ show values
    tdigestByrevrank "td1" (0 NE.:| [2, 4]) >>@? \values ->
        case values of
            [v0, v2, v4] -> do
                HUnit.assertEqual "TDIGEST.BYREVRANK 0" 5 v0
                HUnit.assertBool "TDIGEST.BYREVRANK 2 should be within range" (v2 >= 2 && v2 <= 4)
                HUnit.assertEqual "TDIGEST.BYREVRANK 4" 1 v4
            _ -> HUnit.assertFailure $ "Unexpected TDIGEST.BYREVRANK response: " ++ show values
    tdigestQuantile "td1" (0.0 NE.:| [0.5, 1.0]) >>@? \values ->
        case values of
            [q0, q50, q100] -> do
                HUnit.assertEqual "TDIGEST.QUANTILE 0" 1 q0
                HUnit.assertBool "TDIGEST.QUANTILE 0.5 should be within range" (q50 >= 2 && q50 <= 4)
                HUnit.assertEqual "TDIGEST.QUANTILE 1" 5 q100
            _ -> HUnit.assertFailure $ "Unexpected TDIGEST.QUANTILE response: " ++ show values

    tdigestCdf "td1" (1 NE.:| [3, 5]) >>@? \values ->
        case values of
            [cdf1, cdf3, cdf5] -> do
                HUnit.assertBool "TDIGEST.CDF should be monotonic" (cdf1 <= cdf3 && cdf3 <= cdf5)
                HUnit.assertBool "TDIGEST.CDF last value should be close to 1" (cdf5 >= 0.8)
            _ -> HUnit.assertFailure $ "Unexpected TDIGEST.CDF response: " ++ show values

    tdigestRank "td1" (1 NE.:| [3, 5]) >>@? \values ->
        case values of
            [r1, r3, r5] -> HUnit.assertBool "TDIGEST.RANK should be monotonic" (r1 <= r3 && r3 <= r5)
            _ -> HUnit.assertFailure $ "Unexpected TDIGEST.RANK response: " ++ show values

    tdigestRevrank "td1" (1 NE.:| [3, 5]) >>@? \values ->
        case values of
            [r1, r3, r5] -> HUnit.assertBool "TDIGEST.REVRANK should be monotonic descending" (r1 >= r3 && r3 >= r5)
            _ -> HUnit.assertFailure $ "Unexpected TDIGEST.REVRANK response: " ++ show values

    tdigestTrimmedMean "td1" 0.2 0.8 >>@? \value ->
        HUnit.assertBool "TDIGEST.TRIMMED_MEAN should be within observed range" (value >= 1 && value <= 5)

    tdigestInfo "td1" >>@? \TDigestInfo{..} -> do
        HUnit.assertBool "TDIGEST.INFO compression should be positive" (tdigestInfoCompression > 0)
        HUnit.assertBool "TDIGEST.INFO observations should reflect inserts" (tdigestInfoObservations >= 5)
        HUnit.assertBool "TDIGEST.INFO memory usage should be positive" (tdigestInfoMemoryUsage > 0)

    tdigestCreateOpts "td2" defaultTDigestCreateOpts
        { tdigestCreateCompression = Just 200
        } >>=? Ok
    tdigestAdd "td2" (10 NE.:| [20, 30]) >>=? Ok

    tdigestMerge "td_merged" ("td1" NE.:| ["td2"]) >>@? \status ->
        HUnit.assertEqual "TDIGEST.MERGE status" Ok status
    tdigestInfo "td_merged" >>@? \digestInfo ->
        HUnit.assertBool "TDIGEST.MERGE should populate destination" (tdigestInfoObservations digestInfo >= 8)

    tdigestCreate "td_override" >>=? Ok
    tdigestMergeOpts "td_override" ("td1" NE.:| ["td2"]) defaultTDigestMergeOpts
        { tdigestMergeCompression = Just 150
        , tdigestMergeOverride = True
        } >>=? Ok
    tdigestInfo "td_override" >>@? \digestInfo -> do
        150 HUnit.@=? tdigestInfoCompression digestInfo
        HUnit.assertBool "TDIGEST.MERGE override should populate destination" (tdigestInfoObservations digestInfo >= 8)

    tdigestReset "td1" >>=? Ok
    tdigestInfo "td1" >>@? \digestInfo ->
        HUnit.assertEqual "TDIGEST.RESET observations" 0 (tdigestInfoObservations digestInfo)

-- TimeSeries
--
testTs :: Test
testTs = testCase "timeseries" $ do
    tsCreateOpts "ts:series" defaultTsCreateOpts
        { tsCreateRetention = Just 100000
        , tsCreateEncoding = Just TsCompressed
        , tsCreateChunkSize = Just 128
        , tsCreateDuplicatePolicy = Just TsDuplicateLast
        , tsCreateLabels = [("metric", "temperature"), ("sensor", "alpha")]
        } >>=? Ok

    tsAdd "ts:series" "1000" 1.5 >>=? 1000
    tsAddOpts "ts:series" "2000" 2.5 defaultTsAddOpts
        { tsAddOnDuplicate = Just TsDuplicateLast
        } >>=? 2000
    tsGet "ts:series" >>=? Just (TsSample 2000 2.5)
    tsGetOpts "ts:series" defaultTsGetOpts
        { tsGetLatest = True
        } >>=? Just (TsSample 2000 2.5)

    tsRange "ts:series" "-" "+" >>=? [TsSample 1000 1.5, TsSample 2000 2.5]
    tsRangeOpts "ts:series" "-" "+" defaultTsRangeOpts
        { tsRangeCount = Just 1
        } >>=? [TsSample 1000 1.5]
    tsRevrange "ts:series" "-" "+" >>=? [TsSample 2000 2.5, TsSample 1000 1.5]

    tsAlter "ts:series" defaultTsAlterOpts
        { tsAlterRetention = Just 200000
        , tsAlterChunkSize = Just 256
        , tsAlterDuplicatePolicy = Just TsDuplicateMax
        , tsAlterLabels = [("metric", "temperature"), ("sensor", "beta")]
        } >>=? Ok

    tsIncrbyOpts "ts:counter" 5 defaultTsIncrByOpts
        { tsIncrByTimestamp = Just "1000"
        , tsIncrByLabels = [("metric", "counter"), ("sensor", "alpha")]
        } >>=? 1000
    tsDecrbyOpts "ts:counter" 2 defaultTsIncrByOpts
        { tsIncrByTimestamp = Just "2000"
        } >>=? 2000
    tsGet "ts:counter" >>=? Just (TsSample 2000 3.0)

    tsMadd
        ( ("ts:series", "3000", 3.5) NE.:|
          [ ("ts:counter", "3000", 4.0)
          ]
        ) >>=? [3000, 3000]

    tsQueryindex ("metric=temperature" NE.:| []) >>@? \seriesKeys ->
        HUnit.assertBool "TS.QUERYINDEX should return the labeled series" ("ts:series" `elem` seriesKeys)

    tsMget ("sensor=alpha" NE.:| []) >>@? \reply ->
        HUnit.assertBool "TS.MGET should return payload" (replyHasPayload reply)
    tsMgetOpts ("sensor=alpha" NE.:| []) defaultTsMGetOpts
        { tsMGetLatest = True
        , tsMGetLabels = Just TsWithLabels
        } >>@? \reply ->
            HUnit.assertBool "TS.MGET WITHLABELS should return payload" (replyHasPayload reply)

    tsMrange "-" "+" ("sensor=alpha" NE.:| []) >>@? \reply ->
        HUnit.assertBool "TS.MRANGE should return payload" (replyHasPayload reply)
    tsMrangeOpts "-" "+" ("sensor=alpha" NE.:| []) defaultTsMRangeOpts
        { tsMRangeLabels = Just (TsSelectedLabels ("metric" NE.:| ["sensor"]))
        , tsMRangeAggregation = Just TsAggregationOpts
            { tsAggregationAlign = Nothing
            , tsAggregationType = TsAggregators (TsAggAvg NE.:| [])
            , tsAggregationBucketDuration = 1000
            , tsAggregationBucketTimestamp = Just TsBucketStart
            , tsAggregationEmpty = False
            }
        } >>@? \reply ->
            HUnit.assertBool "TS.MRANGE aggregation should return payload" (replyHasPayload reply)
    tsMrevrange "-" "+" ("sensor=alpha" NE.:| []) >>@? \reply ->
        HUnit.assertBool "TS.MREVRANGE should return payload" (replyHasPayload reply)

    tsCreate "ts:source" >>=? Ok
    tsCreate "ts:dest" >>=? Ok
    tsCreaterule "ts:source" "ts:dest" TsAggAvg 1000 >>=? Ok
    tsAdd "ts:source" "1000" 1 >>=? 1000
    tsAdd "ts:source" "2000" 3 >>=? 2000
    tsAdd "ts:source" "3000" 5 >>=? 3000
    delRuleResult <- tsDelrule "ts:source" "ts:dest"
    liftIO $ case delRuleResult of
        Right Ok -> pure ()
        Left reply | isUnknownCommandReply reply -> pure ()
        Left reply -> HUnit.assertFailure $ "Unexpected TS.DELRULE reply: " ++ show reply
        Right status -> HUnit.assertFailure $ "Unexpected TS.DELRULE status: " ++ show status

    tsInfo "ts:series" >>@? \reply ->
        HUnit.assertBool "TS.INFO should return payload" (replyHasPayload reply)
    tsInfoOpts "ts:series" TsInfoDebug >>@? \reply ->
        HUnit.assertBool "TS.INFO DEBUG should return payload" (replyHasPayload reply)

    tsDel "ts:series" 3000 3000 >>=? 1
    tsRange "ts:series" "-" "+" >>=? [TsSample 1000 1.5, TsSample 2000 2.5]
  where
    replyHasPayload = \case
        Bulk (Just value) -> not (BS.null value)
        MultiBulk (Just replies) -> not (null replies)
        Integer _ -> True
        SingleLine value -> not (BS.null value)
        Error _ -> False
        Bulk Nothing -> False
        MultiBulk Nothing -> False

-- RedisJSON
--
testJSON :: Test
testJSON = testCase "json" $ do
    jsonSet "json:doc" "$"
        "{\"name\":\"base\",\"numbers\":[1,2],\"enabled\":true,\"nested\":{\"inner\":5},\"remove\":\"gone\"}" >>=? Just Ok

    jsonGet "json:doc" >>@? \actual ->
        case actual of
            Just payload -> HUnit.assertBool "JSON.GET should return the object" ("\"name\":\"base\"" `BS.isInfixOf` payload)
            Nothing -> HUnit.assertFailure "JSON.GET returned Nothing"

    jsonGetOpts "json:doc" defaultJSONGetOpts
        { jsonGetIndent = Just "  "
        , jsonGetNewline = Just "\n"
        , jsonGetSpace = Just " "
        , jsonGetPaths = ["$"]
        } >>@? \actual ->
            case actual of
                Just payload -> HUnit.assertBool "JSON.GET opts should format output" ("\n" `BS.isInfixOf` payload)
                Nothing -> HUnit.assertFailure "JSON.GET opts returned Nothing"

    jsonSetOpts "json:nx" "$" "{\"value\":1}" defaultJSONSetOpts
        { jsonSetCondition = Just JSONSetIfNotExists
        } >>=? Just Ok
    jsonSetOpts "json:nx" "$" "{\"value\":2}" defaultJSONSetOpts
        { jsonSetCondition = Just JSONSetIfNotExists
        } >>=? Nothing
    jsonSetOpts "json:nx" "$" "{\"value\":3}" defaultJSONSetOpts
        { jsonSetCondition = Just JSONSetIfExists
        } >>=? Just Ok

    jsonMset
        ( ("json:m1", "$", "{\"name\":\"one\"}") NE.:|
          [ ("json:m2", "$", "{\"name\":\"two\"}")
          ]
        ) >>=? Ok
    jsonMget ("json:m1" NE.:| ["json:m2"]) "$" >>@? \results ->
        HUnit.assertBool "JSON.MGET should return both values" (length results == 2 && all isJust results)

    jsonArrappend "json:doc" "$.numbers" ("3" NE.:| ["4"]) >>@? \reply ->
        HUnit.assertEqual "JSON.ARRAPPEND result" [4] (replyIntegers reply)
    jsonArrlenAt "json:doc" "$.numbers" >>@? \reply ->
        HUnit.assertEqual "JSON.ARRLEN result" [4] (replyIntegers reply)
    jsonArrindexOpts "json:doc" "$.numbers" "2" (JSONArrIndexFromTo 0 3) >>@? \reply ->
        HUnit.assertEqual "JSON.ARRINDEX result" [1] (replyIntegers reply)
    jsonArrinsert "json:doc" "$.numbers" 1 ("9" NE.:| []) >>@? \reply ->
        HUnit.assertEqual "JSON.ARRINSERT result" [5] (replyIntegers reply)
    jsonArrpopAtIndex "json:doc" "$.numbers" 1 >>@? \reply ->
        HUnit.assertBool "JSON.ARRPOP should return popped value" (replyContains "9" reply)
    jsonArrtrim "json:doc" "$.numbers" 1 2 >>@? \reply ->
        HUnit.assertEqual "JSON.ARRTRIM result" [2] (replyIntegers reply)

    jsonNumincrby "json:doc" "$.nested.inner" 5 >>@? \reply ->
        HUnit.assertBool "JSON.NUMINCRBY should update value" (replyContains "10" reply)
    jsonNummultby "json:doc" "$.nested.inner" 2 >>@? \reply ->
        HUnit.assertBool "JSON.NUMMULTBY should update value" (replyContains "20" reply)
    jsonClearAt "json:doc" "$.nested.inner" >>=? 1
    jsonGetOpts "json:doc" defaultJSONGetOpts { jsonGetPaths = ["$.nested.inner"] } >>@? \actual ->
        case actual of
            Just payload -> HUnit.assertBool "JSON.CLEAR should zero numeric value" ("0" `BS.isInfixOf` payload)
            Nothing -> HUnit.assertFailure "JSON.GET nested inner returned Nothing"

    jsonStrappendAt "json:doc" "$.name" "\"!\"" >>@? \reply ->
        HUnit.assertEqual "JSON.STRAPPEND result" [5] (replyIntegers reply)
    jsonToggle "json:doc" "$.enabled" >>@? \reply ->
        HUnit.assertEqual "JSON.TOGGLE result" [False] (replyBools reply)

    jsonObjkeysAt "json:doc" "$" >>@? \reply ->
        HUnit.assertBool "JSON.OBJKEYS should include name" (replyContains "name" reply)
    jsonObjlenAt "json:doc" "$" >>@? \reply ->
        HUnit.assertEqual "JSON.OBJLEN result" [5] (replyIntegers reply)
    jsonTypeAt "json:doc" "$.numbers" >>@? \reply ->
        HUnit.assertBool "JSON.TYPE should report array" (replyContains "array" reply)
    jsonRespAt "json:doc" "$.name" >>@? \reply ->
        HUnit.assertBool "JSON.RESP should return payload" (replyHasPayload reply)
    jsonDebugMemoryAt "json:doc" "$.numbers" >>@? \reply ->
        HUnit.assertBool "JSON.DEBUG MEMORY should return payload" (replyHasPayload reply)

    jsonMerge "json:doc" "$" "{\"merged\":true,\"name\":\"base!\"}" >>=? Ok
    jsonGet "json:doc" >>@? \actual ->
        case actual of
            Just payload -> do
                HUnit.assertBool "JSON.MERGE should add merged field" ("\"merged\":true" `BS.isInfixOf` payload)
                HUnit.assertBool "JSON.MERGE should update name" ("\"name\":\"base!\"" `BS.isInfixOf` payload)
            Nothing -> HUnit.assertFailure "JSON.GET after merge returned Nothing"

    jsonDelAt "json:doc" "$.remove" >>=? 1
    jsonForgetAt "json:doc" "$.merged" >>=? 1
    jsonGet "json:doc" >>@? \actual ->
        case actual of
            Just payload -> do
                HUnit.assertBool "JSON.DEL should remove field" (not ("\"remove\"" `BS.isInfixOf` payload))
                HUnit.assertBool "JSON.FORGET should remove field" (not ("\"merged\"" `BS.isInfixOf` payload))
            Nothing -> HUnit.assertFailure "JSON.GET after delete/forget returned Nothing"

    jsonSet "json:rootArray" "$" "[1,2,3]" >>=? Just Ok
    jsonArrlen "json:rootArray" >>@? \reply ->
        HUnit.assertBool "JSON.ARRLEN root should return payload" (replyHasPayload reply)
    jsonArrpop "json:rootArray" >>@? \reply ->
        HUnit.assertBool "JSON.ARRPOP root should return payload" (replyContains "3" reply)

    jsonSet "json:rootString" "$" "\"abc\"" >>=? Just Ok
    jsonStrappend "json:rootString" "\"d\"" >>@? \reply ->
        HUnit.assertBool "JSON.STRAPPEND root should return payload" (replyHasPayload reply)

    jsonSet "json:clearRoot" "$" "{\"a\":1}" >>=? Just Ok
    jsonClear "json:clearRoot" >>=? 1

    jsonSet "json:deleteRoot" "$" "{\"a\":1}" >>=? Just Ok
    jsonForget "json:deleteRoot" >>=? 1

    jsonSet "json:typeRoot" "$" "{\"a\":1}" >>=? Just Ok
    jsonType "json:typeRoot" >>@? \reply ->
        HUnit.assertBool "JSON.TYPE root should return payload" (replyHasPayload reply)
    jsonObjkeys "json:typeRoot" >>@? \reply ->
        HUnit.assertBool "JSON.OBJKEYS root should return payload" (replyContains "a" reply)
    jsonObjlen "json:typeRoot" >>@? \reply ->
        HUnit.assertBool "JSON.OBJLEN root should return payload" (replyHasPayload reply)
    jsonResp "json:typeRoot" >>@? \reply ->
        HUnit.assertBool "JSON.RESP root should return payload" (replyHasPayload reply)
    jsonDebugMemory "json:typeRoot" >>@? \reply ->
        HUnit.assertBool "JSON.DEBUG MEMORY root should return payload" (replyHasPayload reply)
    jsonDel "json:typeRoot" >>=? 1
  where
    isJust (Just _) = True
    isJust Nothing = False

    replyContains needle = \case
        SingleLine value -> needle `BS.isInfixOf` value
        Error value -> needle `BS.isInfixOf` value
        Integer value -> needle `BS.isInfixOf` Char8.pack (show value)
        Bulk (Just value) -> needle `BS.isInfixOf` value
        Bulk Nothing -> False
        MultiBulk (Just replies) -> any (replyContains needle) replies
        MultiBulk Nothing -> False

    replyHasPayload = \case
        Bulk (Just value) -> not (BS.null value)
        MultiBulk (Just replies) -> not (null replies)
        Integer _ -> True
        SingleLine value -> not (BS.null value)
        Error _ -> False
        Bulk Nothing -> False
        MultiBulk Nothing -> False

    replyIntegers = \case
        Integer value -> [value]
        MultiBulk (Just replies) -> [value | reply <- replies, Right value <- [decode reply :: Either Reply Integer]]
        reply -> case decode reply :: Either Reply Integer of
            Right value -> [value]
            Left _ -> []

    replyBools = \case
        Integer 1 -> [True]
        Integer 0 -> [False]
        MultiBulk (Just replies) -> [value | reply <- replies, Right value <- [decode reply :: Either Reply Bool]]
        reply -> case decode reply :: Either Reply Bool of
            Right value -> [value]
            Left _ -> []

------------------------------------------------------------------------------
-- Cuckoo Filters
--
testCuckooFilter :: Test
testCuckooFilter = testCase "cuckoo filter" $ do
    cfreserveOpts "cf" 1000 defaultCFReserveOpts
        { cfReserveBucketSize = Just 4
        , cfReserveMaxIterations = Just 50
        , cfReserveExpansion = Just 2
        } >>=? Ok

    cfinfo "cf" >>@? \CFInfo{..} -> do
        HUnit.assertBool "cfInfoSize should be positive" (cfInfoSize > 0)
        HUnit.assertBool "cfInfoBuckets should be positive" (cfInfoBuckets > 0)
        1 HUnit.@=? cfInfoFilters
        0 HUnit.@=? cfInfoItemsInserted
        0 HUnit.@=? cfInfoItemsDeleted
        4 HUnit.@=? cfInfoBucketSize
        2 HUnit.@=? cfInfoExpansion
        50 HUnit.@=? cfInfoMaxIterations

    cfadd "cf" "item1" >>=? True
    cfadd "cf" "item1" >>=? True
    cfcount "cf" "item1" >>=? 2
    cfexists "cf" "item1" >>=? True
    cfaddnx "cf" "item1" >>=? False
    cfcount "cf" "item1" >>=? 2

    cfinsert "cf" ("item2" NE.:| ["item3"]) >>=? [CFInsertAdded, CFInsertAdded]
    cfinsertnx "cf" ("item1" NE.:| ["item4"]) >>=? [CFInsertAlreadyExists, CFInsertAdded]
    cfmexists "cf" ("item1" NE.:| ["item2", "item3", "item4", "missing"]) >>=? [True, True, True, True, False]

    cfdel "cf" "item2" >>=? True
    cfcount "cf" "item2" >>=? 0
    cfdel "cf" "item2" >>=? False

------------------------------------------------------------------------------
-- Pub/Sub
--
testPubSub :: Test
testPubSub conn = testCase "pubSub" go conn
  where
    go = do
        -- producer
        asyncProducer <- liftIO $ Async.async $ do
            runRedis conn $ do
                let t = 10^(5 :: Int)
                liftIO $ threadDelay t
                publish "chan1" "hello" >>=? 1
                liftIO $ threadDelay t
                publish "chan2" "world" >>=? 1
            return ()

        -- consumer
        pubSub (subscribe ["chan1"]) $ \msg -> do
            -- ready for a message
            case msg of
                Message{..} -> return
                    (unsubscribe [msgChannel] `mappend` psubscribe ["chan*"])
                PMessage{..} -> return (punsubscribe [msgPattern])

        pubSub (subscribe [] `mappend` psubscribe []) $ \_ -> do
            liftIO $ HUnit.assertFailure "no subs: should return immediately"
            undefined
        liftIO $ Async.wait asyncProducer


------------------------------------------------------------------------------
-- Transaction
--
testTransaction :: Test
testTransaction = testCase "transaction" $ do
    watch ["{same}k1", "{same}k2"] >>=? Ok
    unwatch            >>=? Ok
    set "{same}foo" "foo" >>= \case
      Left _ -> error "error"
      _ -> return ()
    set "{same}bar" "bar" >>= \case
      Left _ -> error "error"
      _ -> return ()
    foobar <- multiExec $ do
        foo <- get "{same}foo"
        bar <- get "{same}bar"
        return $ (,) <$> foo <*> bar
    assert $ foobar == TxSuccess (Just "foo", Just "bar")

testSet7 :: Test
testSet7 = testCase "Set" $ do
    set "hello" "hi" >>=? Ok
    setOpts "hello" "hi" SetOpts{
        setSeconds           = Nothing,
        setMilliseconds      = Nothing,
        setUnixSeconds       = Just 2000,
        setUnixMilliseconds  = Nothing,
        setCondition         = Nothing,
        setKeepTTL           = False
    } >>=? Ok
    setOpts "hello" "hi" SetOpts{
        setSeconds           = Nothing,
        setMilliseconds      = Nothing,
        setUnixSeconds       = Nothing,
        setUnixMilliseconds  = Just 20000,
        setCondition         = Nothing,
        setKeepTTL           = False
    } >>=? Ok
    setOpts "hello" "hi" SetOpts{
        setSeconds           = Nothing,
        setMilliseconds      = Nothing,
        setUnixSeconds       = Nothing,
        setUnixMilliseconds  = Nothing,
        setCondition         = Nothing,
        setKeepTTL           = True
    } >>=? Ok
    setGet "hello" "henlo" >>=? "hi"
    setGetOpts "hello" "henlo2" SetOpts{
        setSeconds           = Nothing,
        setMilliseconds      = Nothing,
        setUnixSeconds       = Nothing,
        setUnixMilliseconds  = Nothing,
        setCondition         = Just Nx,
        setKeepTTL           = False
    } >>=? "henlo"
    return ()

testZAdd7 :: Test
testZAdd7 = testCase "ZADD" $ do
    zadd "set" [(42, "2")] >>=? 1
    zaddOpts "set" [(44, "6")] (defaultZaddOpts {zaddSizeCondition = Just CGT}) >>=? 1
    zaddOpts "set" [(46, "7")] (defaultZaddOpts {zaddSizeCondition = Just CLT}) >>=? 1
    return ()

testExpireTime7 :: Test
testExpireTime7 = testCase "expiretime" $ do
    set "mykey" "Hello" >>=? Ok
    expireat "mykey" 33177117420 >>=? True
    expiretime "mykey" >>=? 33177117420
    pexpireat "mykey" 33177117420000 >>=? True
    pexpiretime "mykey" >>=? 33177117420000

testHashExpire7 :: Test
testHashExpire7 = testCase "hash expire" $ do
    hset "mykey" [("field1", "hello"), ("field2", "world")] >>=? 2

    hexpire "mykey" 60 ("field1" NE.:| ["field2", "missing"]) >>=?
        [ HashFieldExpirationSet
        , HashFieldExpirationSet
        , HashFieldExpirationNoSuchField
        ]

    httl "mykey" ("field1" NE.:| ["field2", "missing"]) >>@? \values ->
        case values of
            [HashFieldExpirationInfo ttl1, HashFieldExpirationInfo ttl2, HashFieldExpirationInfoNoSuchField] -> do
                HUnit.assertBool "HTTL field1 should be positive" (ttl1 > 0 && ttl1 <= 60)
                HUnit.assertBool "HTTL field2 should be positive" (ttl2 > 0 && ttl2 <= 60)
            _ -> HUnit.assertFailure $ "Unexpected HTTL reply: " ++ show values

    hpexpire "mykey" 2000 ("field1" NE.:| ["field2"]) >>=?
        [ HashFieldExpirationSet
        , HashFieldExpirationSet
        ]

    hpttl "mykey" ("field1" NE.:| ["field2"]) >>@? \values ->
        case values of
            [HashFieldExpirationInfo ttl1, HashFieldExpirationInfo ttl2] -> do
                HUnit.assertBool "HPTTL field1 should be positive" (ttl1 > 0 && ttl1 <= 2000)
                HUnit.assertBool "HPTTL field2 should be positive" (ttl2 > 0 && ttl2 <= 2000)
            _ -> HUnit.assertFailure $ "Unexpected HPTTL reply: " ++ show values

    now <- round <$> liftIO getPOSIXTime
    hexpireat "mykey" (now + 60) ("field1" NE.:| ["field2"]) >>=?
        [ HashFieldExpirationSet
        , HashFieldExpirationSet
        ]

    hexpiretime "mykey" ("field1" NE.:| ["field2"]) >>@? \values ->
        case values of
            [HashFieldExpirationInfo ts1, HashFieldExpirationInfo ts2] -> do
                HUnit.assertBool "HEXPIRETIME field1 should be near target" (ts1 >= now && ts1 <= now + 60)
                HUnit.assertBool "HEXPIRETIME field2 should be near target" (ts2 >= now && ts2 <= now + 60)
            _ -> HUnit.assertFailure $ "Unexpected HEXPIRETIME reply: " ++ show values

    nowMs <- round . (* 1000) <$> liftIO getPOSIXTime
    hpexpireat "mykey" (nowMs + 2000) ("field1" NE.:| ["field2"]) >>=?
        [ HashFieldExpirationSet
        , HashFieldExpirationSet
        ]

    hpexpiretime "mykey" ("field1" NE.:| ["field2"]) >>@? \values ->
        case values of
            [HashFieldExpirationInfo ts1, HashFieldExpirationInfo ts2] -> do
                HUnit.assertBool "HPEXPIRETIME field1 should be near target" (ts1 >= nowMs && ts1 <= nowMs + 2000)
                HUnit.assertBool "HPEXPIRETIME field2 should be near target" (ts2 >= nowMs && ts2 <= nowMs + 2000)
            _ -> HUnit.assertFailure $ "Unexpected HPEXPIRETIME reply: " ++ show values

    hexpireOpts "mykey" 10 ("field1" NE.:| [])
        (ExpireOptsTime Nx)
        >>=? [HashFieldExpirationConditionNotMet]

testSintercard7 :: Test
testSintercard7 = testCase "sintercard" $ do
    sadd "{same}bikes:racing:france" ("bike:1" NE.:| ["bike:2", "bike:3"]) >>=? 3
    sadd "{same}bikes:racing:usa" ("bike:1" NE.:| ["bike:4"]) >>=? 2
    sadd "{same}bikes:racing:japan" ("bike:1" NE.:| ["bike:3"]) >>=? 2
    sintercard ("{same}bikes:racing:france" NE.:| ["{same}bikes:racing:usa", "{same}bikes:racing:japan"]) >>=? 1
    sintercardOpts ("{same}bikes:racing:france" NE.:| ["{same}bikes:racing:usa", "{same}bikes:racing:japan"])
        defaultSintercardOpts { sintercardLimit = Just 1 } >>=? 1

testLMPop7 :: Test
testLMPop7 = testCase "lmpop" $ do
    lmpop ("non1" NE.:| ["non2"]) ListLeft >>=? Nothing
    lpush "mylist" ["one", "two", "three", "four", "five"] >>=? 5
    lmpop ("mylist" NE.:| []) ListLeft >>=? Just ("mylist", ["five"])
    lrange "mylist" 0 (-1) >>=? ["four", "three", "two", "one"]

    lpush "mylist2" ["a", "b", "c", "d", "e"] >>=? 5
    lpush "mylist3" ["one", "two", "three", "four", "five"] >>=? 5
    lmpopCount ("mylist" NE.:| ["mylist2"]) ListRight 3 >>=? Just ("mylist", ["one", "two", "three"])
    blmpopCount 1 ("mylist3" NE.:| ["mylist2"]) ListRight 5 >>=? Just ("mylist3", ["one", "two", "three", "four", "five"])
    blmpopCount 1 ("mylist3" NE.:| ["mylist2"]) ListRight 10 >>=? Just ("mylist2", ["a", "b", "c", "d", "e"])

testZMPop7 :: Test
testZMPop7 = testCase "zmpop" $ do
    zadd "{same}zset1" [(1, "one"), (2, "two"), (3, "three")] >>=? 3
    zadd "{same}zset2" [(10, "ten")] >>=? 1
    zmpop ("{same}zset1" NE.:| ["{same}zset2"]) ZPopMax >>=? Just ZPopResponse
        { zPopResponseKey = Just "{same}zset1"
        , zPopResponseValues = [("three", 3)]
        }
    zmpopCount ("{same}zset1" NE.:| ["{same}zset2"]) ZPopMin 2 >>=? Just ZPopResponse
        { zPopResponseKey = Just "{same}zset1"
        , zPopResponseValues = [("one", 1), ("two", 2)]
        }
    bzmpopCount 1 ("{same}zset1" NE.:| ["{same}zset2"]) ZPopMax 2 >>=? Just ZPopResponse
        { zPopResponseKey = Just "{same}zset2"
        , zPopResponseValues = [("ten", 10)]
        }

testFunction7 :: Test
testFunction7 = testCase "function" $ do
    functionFlushOpts FlushOptsSync >>=? Ok
    functionHelp >>@? \helpText ->
        HUnit.assertBool "FUNCTION HELP should return help text" (not (null helpText))

    let libraryCode = "#!lua name=mylib\nredis.register_function('myfunc', function(keys, args) return args[1] end)\nredis.register_function{function_name='myro', callback=function(keys, args) return redis.call('GET', keys[1]) end, flags={ 'no-writes' }}"

    functionLoad libraryCode >>=? "mylib"
    fcall "myfunc" [] ["hello"] >>=? ("hello" :: ByteString)
    set "mykey" "value" >>=? Ok
    fcallReadonly "myro" ["mykey"] [] >>=? ("value" :: ByteString)
    functionList >>@? \reply ->
        case reply of
            MultiBulk (Just _) -> pure ()
            _ -> HUnit.assertFailure $ "Unexpected FUNCTION LIST reply: " ++ show reply
    functionListOpts defaultFunctionListOpts { functionListLibraryName = Just "mylib", functionListWithCode = True } >>@? \reply ->
        case reply of
            MultiBulk (Just _) -> pure ()
            _ -> HUnit.assertFailure $ "Unexpected FUNCTION LIST WITHCODE reply: " ++ show reply
    functionStats >>@? \reply ->
        case reply of
            MultiBulk (Just _) -> pure ()
            _ -> HUnit.assertFailure $ "Unexpected FUNCTION STATS reply: " ++ show reply
    payload <- functionDump
    case payload of
        Left reply -> liftIO $ HUnit.assertFailure $ "Unexpected FUNCTION DUMP reply: " ++ show reply
        Right dumped -> do
            functionDelete "mylib" >>=? Ok
            functionRestore dumped Nothing >>=? Ok
            fcall "myfunc" [] ["restored"] >>=? ("restored" :: ByteString)
    functionFlushOpts FlushOptsSync >>=? Ok

testCommandList7 :: Test
testCommandList7 = testCase "command list" $ do
    commandList >>@? \commands ->
        HUnit.assertBool "COMMAND LIST should contain GET" ("get" `elem` commands)
    commandListOpts (Just $ CommandListFilterByPattern "x*") >>@? \commands -> do
        HUnit.assertBool "pattern-filtered command list should contain xadd" ("xadd" `elem` commands)
        HUnit.assertBool "pattern-filtered command list should exclude get" ("get" `notElem` commands)
    commandListOpts (Just $ CommandListFilterByAclCat "connection") >>@? \commands ->
        HUnit.assertBool "ACLCAT-filtered command list should contain ping" ("ping" `elem` commands)

------------------------------------------------------------------------------
-- Scripting
--
testScripting :: Test
testScripting conn = testCase "scripting" go conn
  where
    go = do
        let script    = "return {false, 42}"
            scriptRes = (False, 42 :: Integer)
        scriptLoad script >>= \case
          Left _ -> error "error"
          Right scriptHash -> do
            eval script [] []                       >>=? scriptRes
            evalsha scriptHash [] []                >>=? scriptRes
            scriptExists [scriptHash, "notAScript"] >>=? [True, False]
            scriptFlush                             >>=? Ok
            -- start long running script from another client
            configSet "lua-time-limit" "100"        >>=? Ok
            evalFinished <- liftIO newEmptyMVar
            asyncScripting <- liftIO $ Async.async $ runRedis conn $ do
                -- we must pattern match to block the thread
                (eval "while true do end" [] []
                    :: Redis (Either Reply Integer)) >>= \case
                    Left _ -> return ()
                    _ -> error "impossible"
                liftIO (putMVar evalFinished ())
                return ()
            liftIO (threadDelay 500000) -- 0.5s
            scriptKill                              >>=? Ok
            () <- liftIO (takeMVar evalFinished)
            liftIO $ Async.wait asyncScripting
            return ()

------------------------------------------------------------------------------
-- Connection
--
testConnectAuth :: String -> PortNumber -> Test
testConnectAuth host port = testCase "connect/auth" $ do
    configSet "requirepass" "pass" >>=? Ok
    liftIO $ do
        c <- checkedConnect defaultConnectInfo { connectAuth = Just "pass", connectAddr = ConnectAddrHostPort host port }
        runRedis c (ping >>=? Pong)
    auth "pass"                    >>=? Ok
    configSet "requirepass" ""     >>=? Ok

testConnectAuthUnexpected :: String -> PortNumber -> Test
testConnectAuthUnexpected host port = testCase "connect/auth/unexpected" $ do
    liftIO $ do
        res <- try $ void $ checkedConnect connInfo
        HUnit.assertEqual "" err res

    where connInfo = defaultConnectInfo { connectAuth = Just "pass", connectAddr = ConnectAddrHostPort host port }
          err = Left $ ConnectAuthError $
                  Error "ERR AUTH <password> called without any password configured for the default user. Are you sure your configuration is correct?"


testConnectAuthAcl :: String -> PortNumber -> Test
testConnectAuthAcl host port = testCase "connect/auth/acl" $ do
   liftIO $ do
      c <- checkedConnect defaultConnectInfo { connectAddr = ConnectAddrHostPort host port }
      runRedis c $ sendRequest  ["ACL", "SETUSER", "test", "on", ">pass", "~*", "&*", "+@all"] >>=? Ok
   liftIO $ do
      c <- checkedConnect defaultConnectInfo{connectAuth=Just "pass", connectUsername=Just "test", connectAddr = ConnectAddrHostPort host port}
      runRedis c (ping >>=? Pong)
   liftIO $ do
      res <- try $ void $ checkedConnect defaultConnectInfo{connectAuth=Just "pass", connectUsername=Just "test1", connectAddr = ConnectAddrHostPort host port}
      HUnit.assertEqual "" err res
   where
     err = Left $ ConnectAuthError $
             Error "WRONGPASS invalid username-password pair or user is disabled."

testConnectDb :: String -> PortNumber -> Test
testConnectDb host port = testCase "connect/db" $ do
    set "connect" "value" >>=? Ok
    liftIO $ void $ do
        c <- checkedConnect defaultConnectInfo { connectDatabase = 1, connectAddr = ConnectAddrHostPort host port }
        runRedis c (get "connect" >>=? Nothing)

testConnectDbUnexisting :: String -> PortNumber -> Test
testConnectDbUnexisting host port = testCase "connect/db/unexisting" $ do
    liftIO $ do
        res <- try $ void $ checkedConnect connInfo
        case res of
          Left (ConnectSelectError _) -> return ()
          _ -> HUnit.assertFailure $
                  "Expected ConnectSelectError, got " ++ show res

    where connInfo = defaultConnectInfo { connectDatabase = 100, connectAddr = ConnectAddrHostPort host port }

testClientUnpause :: Test
testClientUnpause = testCase "client/unpause" $
    clientUnpause >>=? Ok

testEcho :: Test
testEcho = testCase "echo" $
    echo ("value" ) >>=? "value"

testPing :: Test
testPing = testCase "ping" $ ping >>=? Pong

testQuit :: Test
testQuit = testCase "quit" $ quit >>=? Ok

testSelect :: Test
testSelect = testCase "select" $ do
    select 13 >>=? Ok
    select 0 >>=? Ok


------------------------------------------------------------------------------
-- Client
--
testClientId :: Test
testClientId = testCase "client id" $ do
    clientId >>= assert . isRight

testClientName :: Test
testClientName = testCase "client {get,set}name" $ do
    clientGetname >>=? Nothing
    clientSetname "FooBar" >>=? Ok
    clientGetname >>=? Just "FooBar"


------------------------------------------------------------------------------
-- Server
--
testServer :: Test
testServer = testCase "server" $ do
    time >>= \case
      Right (_,_) -> return ()
      Left _ -> error "error"
    slaveof "no" "one" >>=? Ok
    return ()

testBgrewriteaof :: Test
testBgrewriteaof = testCase "bgrewriteaof/bgsave/save" $ do
    save >>=? Ok
    bgsave >>= \case
      Right (Status _) -> return ()
      _ -> error "error"
    -- Redis needs time to finish the bgsave
    liftIO $ threadDelay (10^(5 :: Int))
    bgrewriteaof >>= \case
      Right (Status _) -> return ()
      _ -> error "error"
    return ()

testConfig :: Test
testConfig = testCase "config/auth" $ do
    configGet ["requirepass"]      >>=? [("requirepass", "")]
    configSet "requirepass" "pass" >>=? Ok
    auth "pass"                    >>=? Ok
    configSet "requirepass" ""     >>=? Ok

testFlushall :: Test
testFlushall = testCase "flushall/flushdb" $ do
    flushall >>=? Ok
    flushdb  >>=? Ok

testInfo :: Test
testInfo = testCase "info/lastsave/dbsize" $ do
    info >>= \case
      Left _ -> error "error"
      _ -> return ()
    lastsave >>= \case
      Left _ -> error "error"
      _ -> return ()
    dbsize          >>=? 0
    configResetstat >>=? Ok

testSlowlog :: Test
testSlowlog = testCase "slowlog" $ do
    slowlogReset >>=? Ok
    slowlogGet 5 >>=? []
    slowlogLen   >>=? 0

-- |Starting with Redis 7.0.0, the DEBUG command is disabled by default and must be enabled manually in the Redis Config file
testDebugObject :: Test
testDebugObject = testCase "debugObject/debugSegfault" $ do
    return ()
    -- set "key" "value" >>=? Ok
    -- debugObject "key" >>= \case
      -- Left _ -> error "error"
      -- _ -> return ()
    -- return ()

testScans :: Test
testScans = testCase "scans" $ do
    set "key" "value"       >>=? Ok
    scan cursor0            >>=? (cursor0, ["key"])
    scanOpts cursor0 sOpts1 Nothing >>=? (cursor0, ["key"])
    scanOpts cursor0 sOpts2 Nothing >>=? (cursor0, [])
    where sOpts1 = defaultScanOpts { scanMatch = Just "k*" }
          sOpts2 = defaultScanOpts { scanMatch = Just "not*"}

testSScan :: Test
testSScan = testCase "sscan" $ do
    sadd "set" (NE.fromList ["1"]) >>=? 1
    sscan "set" cursor0     >>=? (cursor0, ["1"])

testHScan :: Test
testHScan = testCase "hscan" $ do
    hset "hash" [("k"::ByteString, "v"::ByteString)] >>=? 1
    hscan "hash" cursor0     >>=? (cursor0, [("k", "v")])

testZScan :: Test
testZScan = testCase "zscan" $ do
    zadd "zset" [(42, "2")] >>=? 1
    zscan "zset" cursor0    >>=? (cursor0, [("2", 42)])

testZrangelex ::Test
testZrangelex = testCase "zrangebylex" $ do
    let testSet = [(10, "aaa"), (10, "abb"), (10, "ccc"), (10, "ddd")]
    zadd "zrangebylex" testSet                          >>=? 4
    zrangebylex "zrangebylex" (Incl "aaa") (Incl "bbb") >>=? ["aaa","abb"]
    zrangebylex "zrangebylex" (Excl "aaa") (Excl "ddd") >>=? ["abb","ccc"]
    zrangebylex "zrangebylex" Minr Maxr                 >>=? ["aaa","abb","ccc","ddd"]
    zrangebylexLimit "zrangebylex" Minr Maxr 2 1        >>=? ["ccc"]

testXAddRead ::Test
testXAddRead = testCase "xadd/xread" $ do
    xadd "{same}somestream8" "123" [("key", "value"), ("key2", "value2")]
    xadd "{same}otherstream" "456" [("key1", "value1")]
    xaddOpts "{same}thirdstream" "*" [("k", "v")]
        $ xaddTrimOpt (Just $ trimOpts (TrimMaxlen 1) TrimExact)
    xaddOpts "{same}thirdstream" "*" [("k", "v")]
        $ xaddTrimOpt (Just $ trimOpts (TrimMaxlen 1) (TrimApprox Nothing))
    xread [("{same}somestream8", "0"), ("{same}otherstream", "0")] >>=? Just [
        XReadResponse {
            stream = "{same}somestream8",
            records = [StreamsRecord{recordId = "123-0", keyValues = [("key", "value"), ("key2", "value2")]}]
        },
        XReadResponse {
            stream = "{same}otherstream",
            records = [StreamsRecord{recordId = "456-0", keyValues = [("key1", "value1")]}]
        }]
    xlen "{same}somestream8" >>=? 1
    where xaddTrimOpt a = XAddOpts{
        xAddTrimOpts = a,
        xAddnoMkStream = False}

testXReadGroup ::Test
testXReadGroup = testCase "XGROUP */xreadgroup/xack" $ void $ runExceptT $ do
    ExceptT $ xadd "somestream8" "123" [("key", "value")]
    ExceptT $ xgroupCreate "somestream8" "somegroup" "0"
    readResult <- ExceptT $ xreadGroup "somegroup" "consumer1" [("somestream8", ">")]
    liftIO $ readResult HUnit.@=? Just [
        XReadResponse {
            stream = "somestream8",
            records = [StreamsRecord{recordId = "123-0", keyValues = [("key", "value")]}]
        }]
    noAcked <- ExceptT $ xack "somestream8" "somegroup" ["123-0"]
    liftIO $ noAcked HUnit.@=? 1
    groupMessages <- ExceptT $ xreadGroup "somegroup" "consumer1" [("somestream8", ">")]
    liftIO $ groupMessages HUnit.@=? Nothing
    setIdOk <- ExceptT $ xgroupSetId "somestream8" "somegroup" "0"
    liftIO $ setIdOk HUnit.@=? Ok
    itemsLeft <- ExceptT $ xgroupDelConsumer "somestream8" "somegroup" "consumer1"
    liftIO $ itemsLeft HUnit.@=? 0
    groupDestroyed <- ExceptT (xgroupDestroy "somestream8" "somegroup")
    liftIO $ groupDestroyed HUnit.@=? True

testXCreateGroup7 ::Test
testXCreateGroup7 = testCase "XGROUP CREATE" $ do
    xgroupCreateOpts "somestream8" "somegroup" "0" XGroupCreateOpts {xGroupCreateMkStream    = True,
                                                                    xGroupCreateEntriesRead = Just "1234"} >>=? Ok
    return ()

testXRange ::Test
testXRange = testCase "xrange/xrevrange" $ do
    xadd "somestream8" "121" [("key1", "value1")]
    xadd "somestream8" "122" [("key2", "value2")]
    xadd "somestream8" "123" [("key3", "value3")]
    xadd "somestream8" "124" [("key4", "value4")]
    xrange "somestream8" "122" "123" Nothing >>=? [
        StreamsRecord{recordId = "122-0", keyValues = [("key2", "value2")]},
        StreamsRecord{recordId = "123-0", keyValues = [("key3", "value3")]}
        ]
    xrevRange "somestream8" "123" "122" Nothing >>=? [
        StreamsRecord{recordId = "123-0", keyValues = [("key3", "value3")]},
        StreamsRecord{recordId = "122-0", keyValues = [("key2", "value2")]}
        ]

testXpending ::Test
testXpending = testCase "xpending" $ do
    xadd "somestream8" "121" [("key1", "value1")]
    xadd "somestream8" "122" [("key2", "value2")]
    xadd "somestream8" "123" [("key3", "value3")]
    xadd "somestream8" "124" [("key4", "value4")]
    xgroupCreate "somestream8" "somegroup" "0"
    xreadGroup "somegroup" "consumer1" [("somestream8", ">")]
    xpendingSummary "somestream8" "somegroup" >>=? XPendingSummaryResponse {
        numPendingMessages = 4,
        smallestPendingMessageId = "121-0",
        largestPendingMessageId = "124-0",
        numPendingMessagesByconsumer = [("consumer1", 4)]
    }
    xpendingDetail "somestream8" "somegroup" "121" "121" 10 defaultXPendingDetailOpts >>@? (\case
            [XPendingDetailRecord{..}] -> do
                messageId HUnit.@=? "121-0"
            bad -> HUnit.assertFailure $ "Unexpectedly got " ++ show bad
            )

testXpending7 ::Test
testXpending7 = testCase "xpending7" $ void $ runExceptT $ do
    ExceptT $ xadd "somestream8" "121" [("key1", "value1")]
    ExceptT $ xadd "somestream8" "122" [("key2", "value2")]
    ExceptT $ xadd "somestream8" "123" [("key3", "value3")]
    ExceptT $ xadd "somestream8" "124" [("key4", "value4")]
    ExceptT $ xgroupCreate "somestream8" "somegroup" "0"
    ExceptT $ xgroupCreate "somestream8" "somegroup2" "0"
    ExceptT $ xreadGroup "somegroup" "consumer1" [("somestream8", ">")]
    ExceptT $ xreadGroup "somegroup2" "consumer2" [("somestream8", ">")]
    ackedCount <- ExceptT $ xack "somestream8" "somegroup" ["121", "122", "123"]
    liftIO $ ackedCount HUnit.@=? 3
    pendingDetails <- ExceptT $ xpendingDetail "somestream8" "somegroup2" "123" "123" 10 XPendingDetailOpts
                    {xPendingDetailIdle     = Just 0,
                     xPendingDetailConsumer = Just "consumer2" }

    liftIO $ case pendingDetails of
        [XPendingDetailRecord{..}] -> do
            messageId HUnit.@=? "123-0"
        bad -> HUnit.assertFailure $ "Unexpectedly got " ++ show bad

testXClaim ::Test
testXClaim =
  testCase "xclaim" $ void $ runExceptT $ do
    storedKey1 <- ExceptT $ xadd "somestream8" "121" [("key1", "value1")]
    liftIO $ storedKey1 HUnit.@=? "121-0"
    storedKey2 <- ExceptT $ xadd "somestream8" "122" [("key2", "value2")]
    liftIO $ storedKey2 HUnit.@=? "122-0"
    groupCreated <- ExceptT $ xgroupCreate "somestream8" "somegroup" "0"
    liftIO $ groupCreated HUnit.@=? Ok
    readResult <- ExceptT $ xreadGroupOpts
      "somegroup"
      "consumer1"
      [("somestream8", ">")]
      (defaultXReadGroupOpts {xReadGroupCount = Just 2})
    liftIO $ readResult HUnit.@=? Just
        [ XReadResponse
            { stream = "somestream8"
            , records =
                [ StreamsRecord
                    {recordId = "121-0", keyValues = [("key1", "value1")]}
                , StreamsRecord
                    {recordId = "122-0", keyValues = [("key2", "value2")]}
                ]
            }
        ]
    claimed <- ExceptT $ xclaim "somestream8" "somegroup" "consumer2" 0 defaultXClaimOpts ["121-0"]
    liftIO $ claimed HUnit.@=? [StreamsRecord {recordId = "121-0", keyValues = [("key1", "value1")]}]
    claimedJustIds <- ExceptT $ xclaimJustIds
      "somestream8"
      "somegroup"
      "consumer2"
      0
      defaultXClaimOpts
      ["122-0"]
    liftIO $ claimedJustIds HUnit.@=? ["122-0"]

testXAutoClaim7 ::Test
testXAutoClaim7 =
  testCase "xautoclaim" $ do
    xadd "somestream8" "121" [("key1", "value1")] >>=? "121-0"
    xadd "somestream8" "122" [("key2", "value2")] >>=? "122-0"
    xgroupCreate "somestream8" "somegroup" "0" >>=? Ok
    xreadGroupOpts "somegroup" "consumer1" [("somestream8", ">")] defaultXReadGroupOpts { xReadGroupCount = Just 2 }

    let opts = XAutoclaimOpts {
        xAutoclaimCount = Just 1
    }
    xautoclaimJustIdsOpts "somestream8" "somegroup" "consumer2" 0 "0-0" opts  >>@? (\case
        XAutoclaimResult{..} -> do
            xAutoclaimClaimedMessages HUnit.@=? ["121-0"]
            xAutoclaimDeletedMessages HUnit.@=? []
            return ())

    xtrim "somestream8" (trimOpts (TrimMaxlen 1) TrimExact) >>=? 1
    xautoclaim "somestream8" "somegroup" "consumer2" 0 "0-0" >>@? (\case
        XAutoclaimResult{..} -> do
            xAutoclaimClaimedMessages HUnit.@=? [StreamsRecord {
                recordId = "122-0",
                keyValues = [("key2", "value2")]
            }]
            xAutoclaimDeletedMessages HUnit.@=? ["121-0"]
            return ()
        )
    return ()

testXAckDel8 :: Test
testXAckDel8 = testCase "xackdel" $ do
    xadd "somestream8-1" "121" [("key1", "value1")] >>=? "121-0"
    xgroupCreate "somestream8-1" "somegroup1" "0" >>=? Ok
    xgroupCreate "somestream8-1" "somegroup2" "0" >>=? Ok
    xreadGroup "somegroup1" "consumer1" [("somestream8-1", ">")] >>@? const (pure ())
    xreadGroup "somegroup2" "consumer2" [("somestream8-1", ">")] >>@? const (pure ())

    let ackedOpts = defaultXEntryDeletionOpts { xEntryDeletionRefPolicy = XRefPolicyAcked }

    xackdelOpts "somestream8-1" "somegroup1" ("121-0" NE.:| []) ackedOpts
        >>=? [XEntryDeletionResultNotDeleted]
    xrange "somestream8-1" "-" "+" Nothing >>@? \records ->
        HUnit.assertEqual "entry should remain until all groups acknowledge it" 1 (length records)

    xackdelOpts "somestream8-1" "somegroup2" ("121-0" NE.:| []) ackedOpts
        >>=? [XEntryDeletionResultDeleted]
    xrange "somestream8-1" "-" "+" Nothing >>=? []

testXDelEx8 :: Test
testXDelEx8 = testCase "xdelex" $ do
    xadd "somestream8" "121" [("key1", "value1")] >>=? "121-0"
    xgroupCreate "somestream8" "somegroup1" "0" >>=? Ok

    let ackedOpts = defaultXEntryDeletionOpts { xEntryDeletionRefPolicy = XRefPolicyAcked }

    xdelexOpts "somestream8" ("121-0" NE.:| []) ackedOpts
        >>=? [XEntryDeletionResultNotDeleted]
    xrange "somestream8" "-" "+" Nothing >>@? \records ->
       HUnit.assertEqual "ACKED should not delete without consumer groups" 1 (length records)

    xgroupCreate "somestream8" "somegroup" "0" >>=? Ok
    xreadGroup "somegroup" "consumer1" [("somestream8", ">")] >>@? const (pure ())
    xdelex "somestream8" ("121-0" NE.:| [])
        >>=? [XEntryDeletionResultDeleted]
    xpendingSummary "somestream8" "somegroup" >>@? \summary ->
        numPendingMessages summary HUnit.@=? 1

testXInfo ::Test
-- This test does not work with pipelining because it relies on the certaino order of commands execution
-- and fails if commands reach different nodes.
testXInfo = testCase "xinfo" $ void $ runExceptT $ do
    _ <- ExceptT $ xadd "somestream8" "121" [("key1", "value1")]
    _ <- ExceptT $ xadd "somestream8" "122" [("key2", "value2")]
    _ <- ExceptT $ xgroupCreate "somestream8" "somegroup" "0"
    _ <- ExceptT $ xreadGroupOpts "somegroup" "consumer1" [("somestream8", ">")] defaultXReadGroupOpts { xReadGroupCount = Just 2 }

    z <- ExceptT $ xinfoConsumers "somestream8" "somegroup"
    liftIO $ case z of
        [XInfoConsumersResponse{..}] -> do
            xinfoConsumerName HUnit.@=? "consumer1"
            xinfoConsumerNumPendingMessages HUnit.@=? 2

        bad -> HUnit.assertFailure $ "Unexpectedly got " ++ show bad

    x <- ExceptT $ xinfoGroups "somestream8"
    liftIO $ case x of
        [XInfoGroupsResponse{..}] -> do
            xinfoGroupsGroupName              HUnit.@=? "somegroup"
            xinfoGroupsNumConsumers           HUnit.@=? 1
            xinfoGroupsNumPendingMessages     HUnit.@=? 2
            xinfoGroupsLastDeliveredMessageId HUnit.@=? "122-0"

            (do xinfoGroupsEntriesRead          HUnit.@=? Nothing -- Redis 6
                xinfoGroupsLag                  HUnit.@=? Nothing) <|?>
                (do xinfoGroupsEntriesRead          HUnit.@=? Just 2 -- Redis 7
                    xinfoGroupsLag                  HUnit.@=? Just 0)

        bad -> HUnit.assertFailure $ "Unexpectedly got " ++ show bad

    a <- ExceptT $ xinfoStream "somestream8"
    liftIO $ case a of
        XInfoStreamResponse{..} -> do
            xinfoStreamLength         HUnit.@=? 2
            xinfoStreamRadixTreeKeys  HUnit.@=? 1
            xinfoStreamRadixTreeNodes HUnit.@=? 2
            xinfoStreamNumGroups      HUnit.@=? 1
            xinfoStreamLastEntryId    HUnit.@=? "122-0"
            xinfoStreamFirstEntry     HUnit.@=? StreamsRecord {
                                                      recordId = "121-0"
                                                    , keyValues = [("key1", "value1")]}
            xinfoStreamLastEntry      HUnit.@=? StreamsRecord {
                                                      recordId = "122-0"
                                                    , keyValues = [("key2", "value2")] }
            (do xinfoMaxDeletedEntryId    HUnit.@=? Nothing -- Redis 6.0
                xinfoEntriesAdded         HUnit.@=? Nothing
                xinfoRecordedFirstEntryId HUnit.@=? Nothing) <|?> -- Redis 7.0
                (do xinfoMaxDeletedEntryId    HUnit.@=? Just "0-0"
                    xinfoEntriesAdded         HUnit.@=? Just 2
                    xinfoRecordedFirstEntryId HUnit.@=? Just "121-0")
        bad -> HUnit.assertFailure $ "Unexpectedly got " ++ show bad
    return ()

testXDel ::Test
testXDel = testCase "xdel" $ do
    xadd "somestream8" "121" [("key1", "value1")]
    xadd "somestream8" "122" [("key2", "value2")]
    xdel "somestream8" ["122"] >>=? 1
    xlen "somestream8" >>=? 1

testVRange84 :: Test
testVRange84 = testCase "vrange" $ do
    vadd "word_embeddings" (0.1 NE.:| [1.2, 0.5]) "Redis" >>=? True
    vadd "word_embeddings" (0.2 NE.:| [1.1, 0.4]) "a7" >>=? True
    vadd "word_embeddings" (0.3 NE.:| [1.0, 0.3]) "b1" >>=? True
    vadd "word_embeddings" (0.4 NE.:| [0.9, 0.2]) "z9" >>=? True

    vrangeCount "word_embeddings" "[Redis" "+" 10 >>=? ["Redis", "a7", "b1", "z9"]
    vrangeCount "word_embeddings" "-" "+" 10 >>=? ["Redis", "a7", "b1", "z9"]
    vrangeCount "word_embeddings" "(a7" "+" 10 >>=? ["b1", "z9"]
    vrangeCount "word_embeddings" "-" "+" (-1) >>=? ["Redis", "a7", "b1", "z9"]

testRedis86Commands :: Test
testRedis86Commands = testCase "redis 8.6 commands" $ do
    xadd "idmp-stream" "*" [("field", "value")] >>@? const (pure ())

    xcfgset "idmp-stream" defaultXCfgSetOpts { xCfgSetIdmpDuration = Just 300 } >>= \case
        Left reply | isUnknownCommandReply reply -> pure ()
        Left reply -> liftIO $ HUnit.assertFailure $ "Unexpected XCFGSET reply: " ++ show reply
        Right Ok -> do
            xcfgset "idmp-stream" defaultXCfgSetOpts
                { xCfgSetIdmpDuration = Just 600
                , xCfgSetIdmpMaxsize = Just 500
                }
                >>=? Ok
        Right status ->
            liftIO $ HUnit.assertFailure $ "Unexpected XCFGSET status: " ++ show status

    hotkeysStop >>= \case
        Left reply | isUnknownCommandReply reply || isHotkeysInactiveReply reply -> pure ()
        Left reply -> liftIO $ HUnit.assertFailure $ "Unexpected HOTKEYS STOP reply: " ++ show reply
        Right Ok -> pure ()
        Right status -> liftIO $ HUnit.assertFailure $ "Unexpected HOTKEYS STOP status: " ++ show status

    hotkeysReset >>= \case
        Left reply | isUnknownCommandReply reply -> pure ()
        Left reply -> liftIO $ HUnit.assertFailure $ "Unexpected HOTKEYS RESET reply: " ++ show reply
        Right Ok -> do
            hotkeysStartOpts
                (HotkeysMetricCPU NE.:| [HotkeysMetricNET])
                defaultHotkeysStartOpts { hotkeysStartTopKCount = Just 2 }
                >>= \case
                    Left reply | isUnknownCommandReply reply -> pure ()
                    Left reply -> liftIO $ HUnit.assertFailure $ "Unexpected HOTKEYS START reply: " ++ show reply
                    Right Ok -> do
                        set "hotkey:001" "payload" >>=? Ok
                        replicateM_ 25 $ do
                            incr "hotkey:counter" >>@? const (pure ())
                            get "hotkey:001" >>=? Just "payload"

                        hotkeysGet >>@? \HotkeysGetResponse{..} -> do
                            HUnit.assertBool "tracking should be active before HOTKEYS STOP" hotkeysGetTrackingActive
                            HUnit.assertBool "sample ratio should be positive" (hotkeysGetSampleRatio >= 1)
                            HUnit.assertBool "selected slots should not be empty" (not $ null hotkeysGetSelectedSlots)
                            HUnit.assertBool "collection duration should be non-negative" (hotkeysGetCollectionDurationMs >= 0)
                            HUnit.assertBool "expected CPU hotkeys to include generated keys" $
                                maybe False (any (\(key, _) -> "hotkey:" `Char8.isPrefixOf` key)) hotkeysGetByCpuTimeUs
                            HUnit.assertBool "expected NET hotkeys to include generated keys" $
                                maybe False (any (\(key, _) -> "hotkey:" `Char8.isPrefixOf` key)) hotkeysGetByNetBytes

                        hotkeysStop >>=? Ok
                        hotkeysGet >>@? \HotkeysGetResponse{..} ->
                            HUnit.assertBool "tracking should be stopped after HOTKEYS STOP" (not hotkeysGetTrackingActive)
                        hotkeysReset >>=? Ok
                    Right status ->
                        liftIO $ HUnit.assertFailure $ "Unexpected HOTKEYS START status: " ++ show status
        Right status ->
            liftIO $ HUnit.assertFailure $ "Unexpected HOTKEYS RESET status: " ++ show status

testRedis88Commands :: Test
testRedis88Commands = testCase "redis 8.8 commands" $ do
    increx "counter88" >>= \case
        Left reply | isUnknownCommandReply reply -> pure ()
        Left reply -> liftIO $ HUnit.assertFailure $ "Unexpected INCREX reply: " ++ show reply
        Right (value, applied) -> do
            liftIO $ (1, 1) HUnit.@=? (value, applied)
            increxBy "counter88" 5 defaultIncrexOpts
                { increxLowerBound = Just 0
                , increxUpperBound = Just 10
                , increxExpiration = Just (IncrexSeconds 60)
                }
                >>=? (6, 5)
            ttl "counter88" >>@? \secondsLeft ->
                HUnit.assertBool "INCREX EX should set a TTL" (secondsLeft >= 0 && secondsLeft <= 60)
            increxByFloat "counter88:float" 0.5 defaultIncrexOpts
                { increxLowerBound = Just 0.0
                , increxUpperBound = Just 1.0
                }
                >>@? \(floatValue, floatApplied) ->
                    HUnit.assertBool "INCREX BYFLOAT should increment the floating-point value" $
                        abs (floatValue - 0.5) < 0.0001 && abs (floatApplied - 0.5) < 0.0001

            streamId <- xadd "stream88" "*" [("field", "value")] >>= \case
                Left reply -> liftIO (HUnit.assertFailure $ "Unexpected XADD reply: " ++ show reply) >> pure ""
                Right sid -> pure sid
            xidmprecord "stream88" "producer-1" "iid-1" streamId >>= \case
                Left reply | isUnknownCommandReply reply -> pure ()
                Left reply -> liftIO $ HUnit.assertFailure $ "Unexpected XIDMPRECORD reply: " ++ show reply
                Right Ok -> pure ()
                Right status -> liftIO $ HUnit.assertFailure $ "Unexpected XIDMPRECORD status: " ++ show status

            xadd "stream88-nack" "1-0" [("field", "value")] >>=? "1-0"
            xgroupCreate "stream88-nack" "group88" "0" >>=? Ok
            xreadGroup "group88" "consumer88" [("stream88-nack", ">")] >>@? const (pure ())
            xnack "stream88-nack" "group88" XNackFail ("1-0" NE.:| []) >>=? 1

            arset "arr88" 0 ("alpha" NE.:| ["beta", "gamma"]) >>= \case
                Left reply | isUnknownCommandReply reply -> pure ()
                Left reply -> liftIO $ HUnit.assertFailure $ "Unexpected ARSET reply: " ++ show reply
                Right createdSlots -> do
                    liftIO $ 3 HUnit.@=? createdSlots
                    arcount "arr88" >>=? 3
                    arlen "arr88" >>=? 3
                    armget "arr88" (0 NE.:| [2, 3]) >>=? [Just "alpha", Just "gamma", Nothing]
                    argetrange "arr88" 0 3 >>=? [Just "alpha", Just "beta", Just "gamma", Nothing]

                    argrep "arr88" "-" "+" (ARGrepExact "beta" NE.:| []) >>=? [1]
                    argrepWithValuesOpts "arr88" "-" "+" (ARGrepMatch "a" NE.:| []) defaultARGrepOpts
                        { arGrepLimit = Just 2
                        }
                        >>=? ARIndexValuePairsResponse [(0, "alpha"), (1, "beta")]

                    arinfo "arr88" >>@? \ARInfoResponse{..} -> do
                        3 HUnit.@=? arInfoCount
                        3 HUnit.@=? arInfoLength
                        HUnit.assertBool "ARINFO should report a positive slice size" (arInfoSliceSize > 0)

                    arseek "arr88" 5 >>=? True
                    arinsert "arr88" ("delta" NE.:| ["epsilon"]) >>=? 6
                    arnext "arr88" >>=? Just 7
                    arlastitems "arr88" 2 >>=? [Just "delta", Just "epsilon"]
                    arlastitemsOpts "arr88" 2 defaultARLastItemsOpts { arLastItemsReverse = True } >>=? [Just "epsilon", Just "delta"]
                    arscanOpts "arr88" 0 10 defaultARScanOpts { arScanLimit = Just 3 } >>=? ARIndexValuePairsResponse [(0, "alpha"), (1, "beta"), (2, "gamma")]
                    ardel "arr88" (1 NE.:| [5]) >>=? 2
                    arcount "arr88" >>=? 3

                    arset "nums88" 0 ("1" NE.:| ["2", "3"]) >>=? 3
                    aropValue "nums88" 0 2 AROpSum >>=? Just "6"
                    aropCount "nums88" 0 2 AROpUsed >>=? Just 3

                    arring "ring88" 3 ("v0" NE.:| ["v1", "v2", "v3"]) >>=? 0
                    arcount "ring88" >>=? 3
                    arlastitems "ring88" 3 >>=? [Just "v1", Just "v2", Just "v3"]

testVectorSet8 :: Test
testVectorSet8 = testCase "vector sets" $ do
    let key = "word_embeddings"
        members = ["apple", "apples", "pear", "pears", "potato"]
        insert element attrs vector =
            vaddOpts key vector element defaultVAddOpts
                { vAddQuantization = Just VAddNoQuant
                , vAddAttributes = attrs
                }

    insert "apple" (Just "{\"len\":5,\"kind\":\"fruit\"}") (1.0 NE.:| [0.0, 0.0]) >>=? True
    insert "apples" (Just "{\"len\":6,\"kind\":\"fruit\"}") (0.9 NE.:| [0.1, 0.0]) >>=? True
    insert "pear" (Just "{\"len\":4,\"kind\":\"fruit\"}") (0.8 NE.:| [0.2, 0.0]) >>=? True
    insert "pears" Nothing (0.75 NE.:| [0.25, 0.05]) >>=? True
    insert "potato" (Just "{\"len\":6,\"kind\":\"vegetable\"}") (0.0 NE.:| [1.0, 0.0]) >>=? True

    vcard key >>=? 5
    vdim key >>=? 3
    vismember key "apple" >>=? True
    vismember key "orange" >>=? False

    vemb key "apple" >>@? \case
        [x, y, z] -> do
            HUnit.assertBool "VEMB should approximately reconstruct the inserted vector" $
                abs (x - 1.0) < 0.001 && abs y < 0.001 && abs z < 0.001
        vector ->
            HUnit.assertFailure $ "Unexpected VEMB response: " ++ show vector

    vembRaw key "apple" >>@? \case
        Just VEmbRawResponse{..} -> do
            VQuantizationFP32 HUnit.@=? vEmbRawQuantization
            HUnit.assertBool "raw vector blob should not be empty" (BS.length vEmbRawData > 0)
            HUnit.assertBool "vector norm should be positive" (vEmbRawNorm > 0)
            Nothing HUnit.@=? vEmbRawRange
        reply ->
            HUnit.assertFailure $ "Unexpected VEMB RAW response: " ++ show reply

    vgetattr key "apple" >>=? Just "{\"len\":5,\"kind\":\"fruit\"}"
    vsetattr key "pears" "{\"len\":5,\"kind\":\"fruit\"}" >>=? True
    vgetattr key "pears" >>=? Just "{\"len\":5,\"kind\":\"fruit\"}"
    vsetattr key "pears" "" >>=? True
    vgetattr key "pears" >>=? Nothing

    vinfo key >>@? \case
        Just VInfoResponse{..} -> do
            HUnit.assertBool "quantization should be reported as f32/fp32" $
                vInfoQuantization == Just "f32" || vInfoQuantization == Just "fp32"
            Just 3 HUnit.@=? vInfoVectorDim
            Just 5 HUnit.@=? vInfoSize
            HUnit.assertBool "max level should be reported" $
                maybe False (>= 0) vInfoMaxLevel
        reply ->
            HUnit.assertFailure $ "Unexpected VINFO response: " ++ show reply

    vlinks key "apple" >>@? \case
        Just (VLinksResponse layers) ->
            HUnit.assertBool "VLINKS should return at least one adjacent element" $
                any (not . null) layers
        reply ->
            HUnit.assertFailure $ "Unexpected VLINKS response: " ++ show reply

    vlinksWithScores key "apple" >>@? \case
        Just (VLinksWithScoresResponse layers) -> do
            HUnit.assertBool "VLINKS WITHSCORES should return at least one adjacent element" $
                any (not . null) layers
            HUnit.assertBool "VLINKS WITHSCORES should only return known members" $
                all (\(neighbor, _) -> neighbor `elem` members)
                    [ pair | layer <- layers, pair <- layer ]
        reply ->
            HUnit.assertFailure $ "Unexpected VLINKS WITHSCORES response: " ++ show reply

    vrandmember key >>@? \member ->
        HUnit.assertBool "VRANDMEMBER should return one of the inserted elements" $
            maybe False (`elem` members) member

    vrandmemberCount key 3 >>@? \randomMembers -> do
        HUnit.assertEqual "VRANDMEMBER count" 3 (length randomMembers)
        HUnit.assertBool "VRANDMEMBER count should only return known members" $
            all (`elem` members) randomMembers

    vrange key "-" "+" >>=? members
    vrangeCount key "[apple" "[pear" 10 >>=? ["apple", "apples", "pear"]

    vsim key (VSimByElement "apple") >>@? \similar -> do
        HUnit.assertBool "VSIM should return at least one match" (not $ null similar)
        case similar of
            firstMatch:_ ->
                HUnit.assertEqual "VSIM first match" "apple" firstMatch
            [] ->
                HUnit.assertFailure "VSIM returned no matches"

    vsimOpts key (VSimByValues (1.0 NE.:| [0.0, 0.0])) defaultVSimOpts { vSimCount = Just 2 } >>@? \similar -> do
        HUnit.assertEqual "VSIM VALUES count" 2 (length similar)
        case similar of
            firstMatch:_ ->
                HUnit.assertEqual "VSIM VALUES first match" "apple" firstMatch
            [] ->
                HUnit.assertFailure "VSIM VALUES returned no matches"

    vsimWithScoresOpts key (VSimByElement "apple") defaultVSimOpts { vSimCount = Just 3 } >>@? \similar -> do
        HUnit.assertEqual "VSIM WITHSCORES count" 3 (length similar)
        case similar of
            (firstMatch, firstScore):_ -> do
                HUnit.assertEqual "VSIM WITHSCORES first match" "apple" firstMatch
                HUnit.assertBool "VSIM WITHSCORES self similarity should be close to 1" $
                    firstScore > 0.99
            [] ->
                HUnit.assertFailure "VSIM WITHSCORES returned no matches"

    vsimWithScoresWithAttribsOpts key (VSimByElement "apple") defaultVSimOpts { vSimCount = Just 3 } >>@? \VSimWithAttribsResponse{..} -> do
        HUnit.assertEqual "VSIM WITHATTRIBS count" 3 (length vSimWithAttribsResults)
        case vSimWithAttribsResults of
            firstMatch:_ -> do
                HUnit.assertEqual "VSIM WITHATTRIBS first match" "apple" (vSimResultElement firstMatch)
                Just "{\"len\":5,\"kind\":\"fruit\"}" HUnit.@=? vSimResultAttributes firstMatch
            [] ->
                HUnit.assertFailure "VSIM WITHATTRIBS returned no matches"

    vrem key "potato" >>=? True
    vismember key "potato" >>=? False
    vcard key >>=? 4

testClusterSlotStats8 :: Test
testClusterSlotStats8 = testCase "cluster slot-stats" $ do
    clusterSlotStatsSlotsRange 0 16383 >>@? \ClusterSlotStatsResponse{..} -> do
        HUnit.assertBool "CLUSTER SLOT-STATS SLOTSRANGE should return at least one slot" $
            not (null clusterSlotStatsResponseEntries)
        forM_ clusterSlotStatsResponseEntries $ \ClusterSlotStatsResponseEntry{..} -> do
            HUnit.assertBool "slot number should be in the valid cluster range" $
                clusterSlotStatsResponseEntrySlot >= 0 && clusterSlotStatsResponseEntrySlot <= 16383
            HUnit.assertBool "key-count should be present" $
                maybe False (>= 0) clusterSlotStatsResponseEntryKeyCount

    clusterSlotStatsOrderByOpts ClusterSlotStatsKeyCount
        defaultClusterSlotStatsOrderByOpts { clusterSlotStatsOrderByLimit = Just 1 }
        >>@? \ClusterSlotStatsResponse{..} ->
            HUnit.assertBool "ORDERBY with LIMIT should return at most one entry" $
                length clusterSlotStatsResponseEntries <= 1

testClusterMigration84 :: Test
testClusterMigration84 = testCase "cluster migration" $ do
    clusterMigrationCancelAll >>@? \cancelled ->
        HUnit.assertBool "cancel count should be non-negative" (cancelled >= 0)

    clusterMigrationStatusAll >>@? \ClusterMigrationStatusResponse{..} ->
        forM_ clusterMigrationStatusTasks $ \ClusterMigrationTask{..} -> do
            HUnit.assertBool "migration task id should not be empty" (clusterMigrationTaskId /= "")
            HUnit.assertBool "migration task retries should be non-negative when present" $
                maybe True (>= 0) clusterMigrationTaskRetries

testXTrim ::Test
testXTrim = testCase "xtrim" $ do
    xadd "somestream8" "121" [("key1", "value1")]
    xadd "somestream8" "122" [("key2", "value2")]
    xadd "somestream8" "123" [("key3", "value3")]
    streamId <- fromRight "" <$> xadd "somestream8" "124" [("key4", "value4")]
    xadd "somestream8" "125" [("key5", "value5")]
    xtrim "somestream8" (trimOpts (TrimMaxlen 3) TrimExact) >>=? 2
    xtrim "somestream8" (trimOpts (TrimMinId streamId) TrimExact) >>=? 1
