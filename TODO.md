
# State of Hedis and TODOs

In order of descending priority.

See repository milestones for more information.

## Github Issues and Pull requests

* Priorities vary
* Some of them overlap with the big-picture issues discussed below.

## Redis API Completeness

The idea is to make Hedis fully compatible with the best of the class
libraries for the other languages. It means that we want features like (in random order):

* Full ACL support.
* Multiplexing (optional)
* Detect broken sockets and reconnect predictably (including cluster environment)
* Exponential backoff with jitter to avoid connection storms
* Error classification
* Retry policy
* Observability
* Good examples
* Full Redis Cluster support
* Hash tags / same-slot validation
* Cluster pipelining
* Cluster scan
* Full sentinel support
* Read from replica (cluster and sentinel)
* Failover behavior
* RESP3 support
* Client-side caching
* Pub/Sub state restoration
* Sharded Pub/Sub
* Latency-based replica reads
* AZ-aware replica reads
* CLIENT CAPA redirect (Valkey)
* OpenTelemetry integration
* Async / streaming ergonomics (?)

Some of the features may be partially implemented and some could be dropped.
