case ARGV[0]
when "marshal", "yaml", "json", "msgpack"
else
  abort "Usage: #$0 marshal|yaml|json|msgpack"
end

require 'object-stream'
require 'socket'

begin
  type = ARGV.shift

  s, t = UNIXSocket.pair

  pid = fork do
    stream = ObjectStream.new(s, type: type)
    10.times do |i|
      stream << [i] # box the int because json needs it
    end
  end

  s.close
  stream = ObjectStream.new(t, type: type)

  puts "try to select"
  until stream.eof? # Otherwise, EOFError is raised at end.
    select([stream]) # Note stream usable as IO.
    
    # Use #read instead of #each or #map so that, in the case of msgpack and
    # yajl, only the available bytes in io are copied to the stream's buffer
    # and parsed to objects.
    stream.read do |obj|
      p obj
    end

    puts "select again"
  end
  puts "t.eof? = #{t.eof?}"
  stream.close

ensure
  Process.wait pid if pid
end
