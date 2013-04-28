object-stream
=============

Stream objects over IO using Marshal, JSON, YAML, or Msgpack.

Note that JSON (using Yajl) and Msgpack both permit suspending partial reads when other input is available, while Marshal and YAML need to read complete objects.
