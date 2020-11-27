module Main (main) where

import qualified Test.Framework as Test
import Database.Redis
import Tests (tests)

main :: IO ()
main = do
    -- We're looking for the cluster on a non-default port to support running
    -- this test in parallel witht the regular non-cluster tests. To quickly
    -- spin up a cluster on this port using docker you can run:
    --
    --     docker run -e "IP=0.0.0.0" -p 7000-7010:7000-7010 grokzen/redis-cluster:5.0.6
    conn <- connectCluster defaultConnectInfo { connectPort = PortNumber 7000 }
    Test.defaultMain (tests conn)
