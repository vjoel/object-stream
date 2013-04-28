# Stream of objects, with any underlying IO.
# Stream is bidirectional if the IO is bidirectional.
module ObjectStream
  include Enumerable
  
  attr_reader :io
  
  MARSHAL_TYPE  = :marshal
  YAML_TYPE     = :yaml
  JSON_TYPE     = :json
  MSGPACK_TYPE  = :msgpack
  
  class << self
    def new io, type: MARSHAL_TYPE, **opts
      cl = stream_class_for(type)
      cl.new io, **opts
    end

    def stream_class_for type
      @stream_class_for ||= {}
      @stream_class_for[type] ||=
        begin
          case type
          when MARSHAL_TYPE
            MarshalStream
          when YAML_TYPE
            require 'yaml'
            YamlStream
          when JSON_TYPE
            require 'yajl'
            require 'yajl/json_gem'
            JsonStream
          when MSGPACK_TYPE
            require 'msgpack'
            MsgpackStream
          else
            raise ArgumentError, "unknown type: #{type.inspect}"
          end
        end
    end
  end
  
  def initialize io, **opts
    @io = io
    unexpect
  end
  
  def expect cl = nil; end
  def unexpect; expect nil; end
  
  def read; end
  def write object; end

  def each
    until io.eof?
      read do |obj|
        yield obj
      end
    end
  end
  
  class MarshalStream
    include ObjectStream
    
    def read
      yield Marshal.load(io)
    end
    
    def write object
      Marshal.dump(object, io)
      self
    end
    alias << write
  end
  
  class YamlStream
    include ObjectStream
    
    def read
      YAML.load_stream(io) do |obj|
        yield obj
      end
    end
    
    def write object
      YAML.dump(object, io)
      self
    end
    alias << write
  end
  
  class JsonStream
    include ObjectStream
    
    attr_accessor :chunk_size

    def initialize io, chunk_size: 2000
      super
      @parser = Yajl::Parser.new
      @encoder = Yajl::Encoder.new
      @chunk_size = chunk_size
    end

    # class cl should define #to_json and cl.from_serialized
    def expect cl = yield
      @expected_class = cl
    end
    
    def read
      @parser.on_parse_complete = proc do |obj|
        yield @expected_class ? @expected_class.from_serialized(obj) : obj
      end
      @parser << io.readpartial(chunk_size)
    end
    
    def write object
      @encoder.encode object, io
      self
    end
    alias << write
  end

  class MsgpackStream
    include ObjectStream
    
    attr_accessor :chunk_size

    def initialize io, chunk_size: 2000
      super
      @unpacker = MessagePack::Unpacker.new
        # don't specify io, so don't have to read all of io in one loop
      
      @packer = MessagePack::Packer.new(io)
      @chunk_size = chunk_size
    end

    # class cl should define #to_msgpack and cl.from_serialized
    def expect cl = yield
      @expected_class = cl
    end
    
    def read
      fill_buffer(chunk_size)
      read_from_buffer do |obj|
        yield obj
      end
    end
    
    def fill_buffer n
      @unpacker.feed(io.readpartial(n))
    end

    def read_from_buffer
      @unpacker.each do |obj|
        yield @expected_class ? @expected_class.from_serialized(obj) : obj
      end
    end
    
    def write object
      @packer.write(object).flush
      self
    end
    alias << write
    
    def write_to_buffer
      @packer.write(object)
      self
    end
    
    def flush_buffer
      @packer.flush
      self
    end
  end
end
