module Database.Redis (
    -- * How To Use This Module
    -- |
    -- Connect to a Redis server:
    --
    -- @
    -- -- connects to localhost:6379
    -- conn <- 'connect' 'defaultConnectInfo'
    -- @
    --
    -- Send commands to the server:
    -- 
    -- @
    -- {-\# LANGUAGE OverloadedStrings \#-}
    -- ...
    -- 'runRedis' conn $ do
    --      'set' \"hello\" \"hello\"
    --      set \"world\" \"world\"
    --      hello <- 'get' \"hello\"
    --      world <- get \"world\"
    --      liftIO $ print (hello,world)
    -- @

    -- ** Command Type Signatures
    -- |Redis commands behave differently when issued in- or outside of a
    --  transaction. To make them work in both contexts, most command functions
    --  have a type signature similar to the following:
    --
    --  @
    --  'echo' :: ('RedisCtx' m f) => ByteString -> m (f ByteString)
    --  @
    --
    --  Here is how to interpret this type signature:
    --
    --  * The argument types are independent of the execution context. 'echo'
    --    always takes a 'ByteString' parameter, whether in- or outside of a
    --    transaction. This is true for all command functions.
    --
    --  * All Redis commands return their result wrapped in some \"container\".
    --    The type @f@ of this container depends on the commands execution
    --    context @m@. The 'ByteString' return type in the example is specific
    --    to the 'echo' command. For other commands, it will often be another
    --    type.
    --
    --  * In the \"normal\" context 'Redis', outside of any transactions,
    --    results are wrapped in an @'Either' 'Reply'@.
    --
    --  * Inside a transaction, in the 'RedisTx' context, results are wrapped in
    --    a 'Queued'.
    --
    --  In short, you can view any command with a 'RedisCtx' constraint in the
    --  type signature, to \"have two types\". For example 'echo' \"has both
    --  types\":
    --
    --  @
    --  echo :: ByteString -> Redis (Either Reply ByteString)
    --  echo :: ByteString -> RedisTx (Queued ByteString)
    --  @
    --
    --  [Exercise] What are the types of 'expire' inside a transaction and
    --    'lindex' outside of a transaction? The solutions are at the very
    --    bottom of this page.

    -- ** Lua Scripting
    -- |Lua values returned from the 'eval' and 'evalsha' functions will be
    --  converted to Haskell values by the 'decode' function from the
    --  'RedisResult' type class.
    --
    --  @
    --  Lua Type      | Haskell Type       | Conversion Example
    --  --------------|--------------------|-----------------------------
    --  Number        | Integer            | 1.23   => 1
    --  String        | ByteString, Double | \"1.23\" => \"1.23\" or 1.23
    --  Boolean       | Bool               | false  => False
    --  Table         | List               | {1,2}  => [1,2]
    --  @
    --
    --  Additionally, any of the Haskell types from the table above can be
    --  wrapped in a 'Maybe':
    --
    --  @
    --  42  => Just 42 :: Maybe Integer
    --  nil => Nothing :: Maybe Integer
    --  @
    --
    --  Note that Redis imposes some limitations on the possible conversions:
    --
    --  * Lua numbers can only be converted to Integers. Only Lua strings can be
    --    interpreted as Doubles.
    --
    --  * Associative Lua tables can not be converted at all. Returned tables
    --   must be \"arrays\", i.e. indexed only by integers.
    --
    --  The Redis Scripting website (<http://redis.io/commands/eval>)
    --  documents the exact semantics of the scripting commands and value
    --  conversion.
    
    -- ** Automatic Pipelining
    -- |Commands are automatically pipelined as much as possible. For example,
    --  in the above \"hello world\" example, all four commands are pipelined.
    --  Automatic pipelining makes use of Haskell's laziness. As long as a
    --  previous reply is not evaluated, subsequent commands can be pipelined.
    --
    --  Automatic pipelining also works across several calls to 'runRedis', as
    --  long as replies are only evaluated /outside/ the 'runRedis' block.
    --
    --  To keep memory usage low, the number of requests \"in the pipeline\" is
    --  limited (per connection) to 1000. After that number, the next command is
    --  sent only when at least one reply has been received. That means, command
    --  functions may block until there are less than 1000 outstanding replies.
    --
    
    -- ** Error Behavior
    -- |
    --  [Operations against keys holding the wrong kind of value:] Outside of a
    --    transaction, if the Redis server returns an 'Error', command functions
    --    will return 'Left' the 'Reply'. The library user can inspect the error
    --    message to gain  information on what kind of error occured.
    --
    --  [Connection to the server lost:] In case of a lost connection, command
    --    functions throw a 'ConnectionLostException'. It can only be caught
    --    outside of 'runRedis'.
    --
    --  [Exceptions:] Any exceptions can only be caught /outside/ of 'runRedis'.
    --    This way the connection pool can properly close the connection, making
    --    sure it is not left in an unusable state, e.g. closed or inside a
    --    transaction.
    --
    
    -- * The Redis Monad
    Redis(), runRedis,
    RedisCtx(), MonadRedis(),

    -- * Connection
    Connection, connect,
    ConnectInfo(..),defaultConnectInfo,
    HostName,PortID(..),
    
    -- * Commands
	module Database.Redis.Commands,
    
    -- * Transactions
    module Database.Redis.Transactions,
    
    -- * Pub\/Sub
    module Database.Redis.PubSub,

    -- * Low-Level Command API
    sendRequest,
    Reply(..),Status(..),RedisResult(..),ConnectionLostException(..),
    
    -- |[Solution to Exercise]
    --
    --  Type of 'expire' inside a transaction:
    --
    --  > expire :: ByteString -> Integer -> RedisTx (Queued Bool)
    --
    --  Type of 'lindex' outside of a transaction:
    --
    --  > lindex :: ByteString -> Integer -> Redis (Either Reply ByteString)
    --
) where

import Database.Redis.Core
import Database.Redis.PubSub
import Database.Redis.Protocol
import Database.Redis.ProtocolPipelining
    (HostName, PortID(..), ConnectionLostException(..))
import Database.Redis.Transactions
import Database.Redis.Types

import Database.Redis.Commands
