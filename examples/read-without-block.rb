require 'object-stream'
require 'socket'

begin
  type = ObjectStream::MSGPACK_TYPE

  s, t = UNIXSocket.pair

  pid = fork do
    stream = ObjectStream.new(s, type: type)
    100.times do |i|
      stream << [i]
    end
  end

  s.close
  stream = ObjectStream.new(t, type: type)

  until stream.eof?
    p stream.read
  end

ensure
  Process.wait pid if pid
end
