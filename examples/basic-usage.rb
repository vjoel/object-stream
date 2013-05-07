case ARGV[0]
when "marshal", "yaml", "json", "msgpack"
else
  abort "Usage: #$0 marshal|yaml|json|msgpack"
end

require 'object-stream'
require 'tmpdir'

begin
  dir = Dir.mktmpdir "stream-"
  dumpfile = File.join(dir, "dump")

  type = ARGV.shift
  
  File.open(dumpfile, "w") do |f|
    stream = ObjectStream.new(f, type: type)
    p stream
    stream << "foo" << [:bar, 42] << {"String" => "string"}
  end
  
  data = File.read(dumpfile)
  puts "===== #{data.size} bytes:"
  case type
  when ObjectStream::MARSHAL_TYPE, ObjectStream::MSGPACK_TYPE
    puts data.inspect
  when ObjectStream::YAML_TYPE, ObjectStream::JSON_TYPE
    puts data
  end
  puts "====="
  
  a = File.open(dumpfile, "r") do |f|
    stream = ObjectStream.new(f, type: type)
    stream.map do |obj|
      #p obj
      obj
    end
  end
  p a

ensure
  FileUtils.remove_entry dir
end
