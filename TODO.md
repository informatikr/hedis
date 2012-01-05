# TODO List

## Certainly

- runRedis: take [Reply] from the MVar, Redis holds [Reply] in State
- PubSub: how to disallow runRedis inside PubSub?
- Manual implementation of blacklisted commands
- More instances for argument type class
- Add Redis* instances for
    - containers
    - unordered-containers
    - vector
    - Text
- Benchmark
    - include pathological cases with a lot of list appending when building reqs
- Test to check if pipelining works


## Maybe

- clean up GenCmds.hs
    - use Text.Lazy.Builder?
- use pool library by bos for connection pooling
- AUTH when connecting (User can do this easily, right after connecting)
