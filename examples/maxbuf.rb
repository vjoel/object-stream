# The MsgpackStream can detect when too many bytes have been read without
# complete parsing of an object.

require 'object-stream'
require 'stringio'

sio = StringIO.new
stream = ObjectStream.new(sio, type: ObjectStream::MSGPACK_TYPE)
stream << "This is a very long sentence, and possibly a denial-of-service attack!"

sio.rewind
stream = ObjectStream.new(sio, type: ObjectStream::MSGPACK_TYPE, maxbuf: 20)
begin
  stream.to_a
rescue ObjectStream::OverflowError => ex
  puts ex # => Exceeded buffer limit by 53 bytes.
end
