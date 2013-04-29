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

  type = ARGV.shift.intern
  
  class A
    def initialize x, y
      @x, @y = x, y
    end
    
    def to_msgpack pk = nil
      case pk
      when MessagePack::Packer
        pk.write_array_header(2)
        pk.write @x
        pk.write @y
        return pk
      
      else # nil or IO
        MessagePack.pack(self, pk)
      end
    end
    
    def to_json
      [@x, @y].to_json
    end
    
    def self.from_serialized ary
      new *ary
    end
  end

  File.open(dumpfile, "w") do |f|
    stream = ObjectStream.new(f, type: type)
    p stream
    stream << "foo" << [:bar, 42] << {"String" => "string"} << "A" << A.new(3,6)
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
      stream.expect {obj == "A" and A}
        # code inside block won't be executed in ases where object class
        # is passed in the data itself (marshal, yaml)
      obj
    end
  end
  p a

ensure
  FileUtils.remove_entry dir
end
