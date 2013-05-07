case ARGV[0]
when "marshal", "yaml", "json", "msgpack"
else
  abort "Usage: #$0 marshal|yaml|json|msgpack"
end

require 'object-stream'

begin
  type = ARGV.shift

  rd, wr = IO.pipe

  pid = fork do
    stream = ObjectStream.new(wr, type: type)
    10.times do |i|
      stream << [i] # box the int because json needs it
    end
  end

  wr.close
  stream = ObjectStream.new(rd, type: type)

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
  puts "rd.eof? = #{rd.eof?}"
  stream.close

ensure
  Process.wait pid if pid
end
