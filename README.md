object-stream
=============

Stream objects over IO using Marshal, JSON, YAML, or Msgpack.

Note that JSON (using Yajl) and Msgpack both permit suspending partial reads when other input is available, while Marshal and YAML need to read complete objects. So, using Marshal or YAML in a single thread (such as a select loop) may lead to blocking if one stream has not produced a complete object. See examples/slow-sender.rb.

