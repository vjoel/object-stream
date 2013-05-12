require 'object-stream'
require 'stringio'

sio = StringIO.new
stream = ObjectStream.new(sio, type: ObjectStream::MSGPACK_TYPE)
stream.write_to_outbox "and now for something"
stream << "completely different"

sio.rewind
stream = ObjectStream.new(sio, type: ObjectStream::MSGPACK_TYPE)
puts stream.to_a

__END__

Output:

and now for something
completely different

