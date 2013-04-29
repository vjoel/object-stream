case ARGV[0]
when "marshal", "yaml", "json", "msgpack"
else
  abort "Usage: #$0 marshal|yaml|json|msgpack"
end

require 'object-stream'
require 'socket'
require 'stringio'

begin
  type = ARGV.shift.intern

  s, t = UNIXSocket.pair

  pid = fork do
    sio = StringIO.new
    stream = ObjectStream.new(sio, type: type)
    10.times do |i|
      stream << "foo bar #{i}"
    end
    
    sio.rewind
    stream2 = ObjectStream.new(sio, type: type)
    stream2.each_with_index do |x, i|
      raise unless x == "foo bar #{i}"
    end
    
    sio.rewind
    data = sio.read
    pos = data.index "bar 5"
    raise unless pos < data.size - 10 # assume strings not munged
    s.write data[0...pos]
    puts "simulating a slow sender -- " +
         "see if receiver blocks or stops reading and goes back to select"
    sleep 0.1
    s.write data[pos...pos+1]
    sleep 0.1
    s.write data[pos+1...pos+2]
    sleep 0.1
    s.write data[pos+2..-1]
  end

  s.close
  stream = ObjectStream.new(t, type: type)

  select_count = 0
  empty_read_count = 0
  until stream.eof? # Otherwise, EOFError is raised at end.
    select_count += 1
    puts "select #{select_count}"
    select([stream]) # Note stream usable as IO.
    
    # Use #read instead of #each or #map so that, in the case of msgpack and
    # yajl, only the available bytes in io are copied to the stream's buffer
    # and parsed to objects.
    obj_count = 0
    stream.read do |obj|
      p obj
      obj_count += 1
    end
    if obj_count == 0
      empty_read_count += 1
    end
  end
  
  stream.close
  if select_count > 1 and empty_read_count > 0
    puts "For #{type}, slow sender did not block the receiver!"
  else
    puts "For #{type}, slow sender blocked the receiver!"
  end

ensure
  Process.wait pid if pid
end
