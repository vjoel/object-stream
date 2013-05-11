case ARGV[0]
when "marshal", "yaml", "json", "msgpack"
else
  abort "Usage: #$0 marshal|yaml|json|msgpack"
end

type = ARGV.shift

require 'object-stream'
require 'socket'

Socket.do_not_reverse_lookup = true
s = UDPSocket.new; s.bind 'localhost', 0
t = UDPSocket.new; t.bind 'localhost', 0
s.connect *t.addr.values_at(2,1)
t.connect *s.addr.values_at(2,1)

th1 = Thread.new do
  stream = ObjectStream.new(s, type: type)
  10.times do |i|
    stream << [i]
  end
  stream << "Bye."
end

th2 = Thread.new do
  stream = ObjectStream.new(t, type: type)
  stream.each do |obj|
    p obj
    break if /bye/i === obj
  end
end

th1.join
th2.join
