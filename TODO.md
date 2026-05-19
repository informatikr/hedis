
# State of Hedis and TODOs

In order of descending priority.

See repository milestones for more information.


## Github Issues and Pull requests

* Priorities vary
* Some of them overlap with the big-picture issues discussed below.


## Redis API Completeness

The idea of Hedis is to support all Redis commands by having one typesafe
function per command.

* Full features support of the Redis cluster.
  At this point there are only few leftover issues for redis cluster support.

* Support of the PubSub protocol.

* Support of Redis 5, 6, 7 features.

* Mapping of Haskell types to Redis types: simplicity and convenience vs.
  correctness (Some issues and pull requests on this topic).
  1. All containers are Haskell lists (current approach):
    - nice list syntax.
    - easy conversion to all collection types.
    - No real loss of safety for return types
    - can fail for arguments (list vs. non-empty)
  2. "correct" container types for each Redis type:
    - Non-empty lists (unconvenient syntax?)
    - Sets
      - Which set type, Set vs HashSet vs ..
      - Redis already returns "sets" in the sense that each element exists only
        once in the returned list.
    - Maps
    - etc.

## Command Return Types

Currently every command returns the result wrapped in `Maybe Reply`. This is
"what Redis returns" but it's unconvenient to use.

* Return the results "unwrapped" and throw an exception when the reply is an
  error or can not be decoded to the desired return type.
* Does this work with the `Queued` return type in Mult/Exec?
