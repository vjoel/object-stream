# The marshal and yaml serializers preserve the difference between strings and
# symbols, but msgpack and json cannot: the formats only allow strings. However,
# sometimes we prefer to write programs that work with symbols even though the
# serialized data contain strings. On the write end of a stream, that is already
# possible: symbols are converted to strings as they are written.
#
# The symbolize keys feature solves the problem on the read end of a stream. It
# configures msgpack and json (yajl) to de-serialize strings as symbols. This
# can be more efficient, since it generates fewer string objects. It's also
# efficient and convenient to avoid conversions when connecting to other
# libraries that expect symbols, such as the Sequel database interface.
#
# Keep in mind that Ruby, as of version 2.1, does not garbage collect symbols
# (though this may be coming in 2.2). So this feature can lead to unbounded
# memory use as new, different symbols keep arriving. Only use it if (a) the set
# of symbols is bounded (and small), or (b) the program has a short lifespan, or
# (c) you can monitor the program's memory use and restart it as needed.
#
# It's safe for one end of a stream to use this option even if the other end
# does not: the stream itself is not affected, only the interface changes.

type = ARGV.shift || "msgpack"

case type
when "marshal", "yaml", "json", "msgpack"
else
  abort "Usage: #$0 marshal|yaml|json|msgpack"
end

require 'object-stream'
require 'stringio'

sio = StringIO.new
stream = ObjectStream.new(sio, type: type, symbolize_keys: true)
stream << {x: 1, y: 2, z: 3}

sio.rewind
p stream.read
