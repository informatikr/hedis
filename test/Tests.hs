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
    xadd "{same}somestream" "123" [("key", "value"), ("key2", "value2")]
    xadd "{same}otherstream" "456" [("key1", "value1")]
    xaddOpts "{same}thirdstream" "*" [("k", "v")]
        $ xaddTrimOpt (Just $ trimOpts (TrimMaxlen 1) TrimExact)
    xaddOpts "{same}thirdstream" "*" [("k", "v")]
        $ xaddTrimOpt (Just $ trimOpts (TrimMaxlen 1) (TrimApprox Nothing))
    xread [("{same}somestream", "0"), ("{same}otherstream", "0")] >>=? Just [
        XReadResponse {
            stream = "{same}somestream",
            records = [StreamsRecord{recordId = "123-0", keyValues = [("key", "value"), ("key2", "value2")]}]
        },
        XReadResponse {
            stream = "{same}otherstream",
            records = [StreamsRecord{recordId = "456-0", keyValues = [("key1", "value1")]}]
        }]
    xlen "{same}somestream" >>=? 1
    where xaddTrimOpt a = XAddOpts{
        xAddTrimOpts = a,
        xAddnoMkStream = False}

testXReadGroup ::Test
testXReadGroup = testCase "XGROUP */xreadgroup/xack" $ void $ runExceptT $ do
    ExceptT $ xadd "somestream" "123" [("key", "value")]
    ExceptT $ xgroupCreate "somestream" "somegroup" "0"
    readResult <- ExceptT $ xreadGroup "somegroup" "consumer1" [("somestream", ">")]
    liftIO $ readResult HUnit.@=? Just [
        XReadResponse {
            stream = "somestream",
            records = [StreamsRecord{recordId = "123-0", keyValues = [("key", "value")]}]
        }]
    noAcked <- ExceptT $ xack "somestream" "somegroup" ["123-0"]
    liftIO $ noAcked HUnit.@=? 1
    groupMessages <- ExceptT $ xreadGroup "somegroup" "consumer1" [("somestream", ">")]
    liftIO $ groupMessages HUnit.@=? Nothing
    setIdOk <- ExceptT $ xgroupSetId "somestream" "somegroup" "0"
    liftIO $ setIdOk HUnit.@=? Ok
    itemsLeft <- ExceptT $ xgroupDelConsumer "somestream" "somegroup" "consumer1"
    liftIO $ itemsLeft HUnit.@=? 0
    groupDestroyed <- ExceptT (xgroupDestroy "somestream" "somegroup")
    liftIO $ groupDestroyed HUnit.@=? True

testXCreateGroup7 ::Test
testXCreateGroup7 = testCase "XGROUP CREATE" $ do
    xgroupCreateOpts "somestream" "somegroup" "0" XGroupCreateOpts {xGroupCreateMkStream    = True,
                                                                    xGroupCreateEntriesRead = Just "1234"} >>=? Ok
    return ()

testXRange ::Test
testXRange = testCase "xrange/xrevrange" $ do
    xadd "somestream" "121" [("key1", "value1")]
    xadd "somestream" "122" [("key2", "value2")]
    xadd "somestream" "123" [("key3", "value3")]
    xadd "somestream" "124" [("key4", "value4")]
    xrange "somestream" "122" "123" Nothing >>=? [
        StreamsRecord{recordId = "122-0", keyValues = [("key2", "value2")]},
        StreamsRecord{recordId = "123-0", keyValues = [("key3", "value3")]}
        ]
    xrevRange "somestream" "123" "122" Nothing >>=? [
        StreamsRecord{recordId = "123-0", keyValues = [("key3", "value3")]},
        StreamsRecord{recordId = "122-0", keyValues = [("key2", "value2")]}
        ]

testXpending ::Test
testXpending = testCase "xpending" $ do
    xadd "somestream" "121" [("key1", "value1")]
    xadd "somestream" "122" [("key2", "value2")]
    xadd "somestream" "123" [("key3", "value3")]
    xadd "somestream" "124" [("key4", "value4")]
    xgroupCreate "somestream" "somegroup" "0"
    xreadGroup "somegroup" "consumer1" [("somestream", ">")]
    xpendingSummary "somestream" "somegroup" >>=? XPendingSummaryResponse {
        numPendingMessages = 4,
        smallestPendingMessageId = "121-0",
        largestPendingMessageId = "124-0",
        numPendingMessagesByconsumer = [("consumer1", 4)]
    }
    xpendingDetail "somestream" "somegroup" "121" "121" 10 defaultXPendingDetailOpts >>@? (\case
            [XPendingDetailRecord{..}] -> do
                messageId HUnit.@=? "121-0"
            bad -> HUnit.assertFailure $ "Unexpectedly got " ++ show bad
            )

testXpending7 ::Test
testXpending7 = testCase "xpending7" $ void $ runExceptT $ do
    ExceptT $ xadd "somestream" "121" [("key1", "value1")]
    ExceptT $ xadd "somestream" "122" [("key2", "value2")]
    ExceptT $ xadd "somestream" "123" [("key3", "value3")]
    ExceptT $ xadd "somestream" "124" [("key4", "value4")]
    ExceptT $ xgroupCreate "somestream" "somegroup" "0"
    ExceptT $ xgroupCreate "somestream" "somegroup2" "0"
    ExceptT $ xreadGroup "somegroup" "consumer1" [("somestream", ">")]
    ExceptT $ xreadGroup "somegroup2" "consumer2" [("somestream", ">")]
    ackedCount <- ExceptT $ xack "somestream" "somegroup" ["121", "122", "123"]
    liftIO $ ackedCount HUnit.@=? 3
    pendingDetails <- ExceptT $ xpendingDetail "somestream" "somegroup2" "123" "123" 10 XPendingDetailOpts
                    {xPendingDetailIdle     = Just 0,
                     xPendingDetailConsumer = Just "consumer2" }

    liftIO $ case pendingDetails of
        [XPendingDetailRecord{..}] -> do
            messageId HUnit.@=? "123-0"
        bad -> HUnit.assertFailure $ "Unexpectedly got " ++ show bad

testXClaim ::Test
testXClaim =
  testCase "xclaim" $ void $ runExceptT $ do
    storedKey1 <- ExceptT $ xadd "somestream" "121" [("key1", "value1")]
    liftIO $ storedKey1 HUnit.@=? "121-0"
    storedKey2 <- ExceptT $ xadd "somestream" "122" [("key2", "value2")]
    liftIO $ storedKey2 HUnit.@=? "122-0"
    groupCreated <- ExceptT $ xgroupCreate "somestream" "somegroup" "0"
    liftIO $ groupCreated HUnit.@=? Ok
    readResult <- ExceptT $ xreadGroupOpts
      "somegroup"
      "consumer1"
      [("somestream", ">")]
      (defaultXReadGroupOpts {xReadGroupCount = Just 2})
    liftIO $ readResult HUnit.@=? Just
        [ XReadResponse
            { stream = "somestream"
            , records =
                [ StreamsRecord
                    {recordId = "121-0", keyValues = [("key1", "value1")]}
                , StreamsRecord
                    {recordId = "122-0", keyValues = [("key2", "value2")]}
                ]
            }
        ]
    claimed <- ExceptT $ xclaim "somestream" "somegroup" "consumer2" 0 defaultXClaimOpts ["121-0"]
    liftIO $ claimed HUnit.@=? [StreamsRecord {recordId = "121-0", keyValues = [("key1", "value1")]}]
    claimedJustIds <- ExceptT $ xclaimJustIds
      "somestream"
      "somegroup"
      "consumer2"
      0
      defaultXClaimOpts
      ["122-0"]
    liftIO $ claimedJustIds HUnit.@=? ["122-0"]

testXAutoClaim7 ::Test
testXAutoClaim7 =
  testCase "xautoclaim" $ do
    xadd "somestream" "121" [("key1", "value1")] >>=? "121-0"
    xadd "somestream" "122" [("key2", "value2")] >>=? "122-0"
    xgroupCreate "somestream" "somegroup" "0" >>=? Ok
    xreadGroupOpts "somegroup" "consumer1" [("somestream", ">")] defaultXReadGroupOpts { xReadGroupCount = Just 2 }

    let opts = XAutoclaimOpts {
        xAutoclaimCount = Just 1
    }
    xautoclaimJustIdsOpts "somestream" "somegroup" "consumer2" 0 "0-0" opts  >>@? (\case
        XAutoclaimResult{..} -> do
            xAutoclaimClaimedMessages HUnit.@=? ["121-0"]
            xAutoclaimDeletedMessages HUnit.@=? []
            return ())

    xtrim "somestream" (trimOpts (TrimMaxlen 1) TrimExact) >>=? 1
    xautoclaim "somestream" "somegroup" "consumer2" 0 "0-0" >>@? (\case
        XAutoclaimResult{..} -> do
            xAutoclaimClaimedMessages HUnit.@=? [StreamsRecord {
                recordId = "122-0",
                keyValues = [("key2", "value2")]
            }]
            xAutoclaimDeletedMessages HUnit.@=? ["121-0"]
            return ()
        )
    return ()

testXInfo ::Test
-- This test does not work with pipelining because it relies on the certaino order of commands execution
-- and fails if commands reach different nodes.
testXInfo = testCase "xinfo" $ void $ runExceptT $ do
    _ <- ExceptT $ xadd "somestream" "121" [("key1", "value1")]
    _ <- ExceptT $ xadd "somestream" "122" [("key2", "value2")]
    _ <- ExceptT $ xgroupCreate "somestream" "somegroup" "0"
    _ <- ExceptT $ xreadGroupOpts "somegroup" "consumer1" [("somestream", ">")] defaultXReadGroupOpts { xReadGroupCount = Just 2 }

    z <- ExceptT $ xinfoConsumers "somestream" "somegroup"
    liftIO $ case z of
        [XInfoConsumersResponse{..}] -> do
            xinfoConsumerName HUnit.@=? "consumer1"
            xinfoConsumerNumPendingMessages HUnit.@=? 2

        bad -> HUnit.assertFailure $ "Unexpectedly got " ++ show bad

    x <- ExceptT $ xinfoGroups "somestream"
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

    a <- ExceptT $ xinfoStream "somestream"
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
    xadd "somestream" "121" [("key1", "value1")]
    xadd "somestream" "122" [("key2", "value2")]
    xdel "somestream" ["122"] >>=? 1
    xlen "somestream" >>=? 1

testXTrim ::Test
testXTrim = testCase "xtrim" $ do
    xadd "somestream" "121" [("key1", "value1")]
    xadd "somestream" "122" [("key2", "value2")]
    xadd "somestream" "123" [("key3", "value3")]
    streamId <- fromRight "" <$> xadd "somestream" "124" [("key4", "value4")]
    xadd "somestream" "125" [("key5", "value5")]
    xtrim "somestream" (trimOpts (TrimMaxlen 3) TrimExact) >>=? 2
    xtrim "somestream" (trimOpts (TrimMinId streamId) TrimExact) >>=? 1
