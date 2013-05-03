# Stream of objects, with any underlying IO.
# Stream is bidirectional if the IO is bidirectional.
module ObjectStream
  include Enumerable
  
  attr_reader :io
  attr_accessor :peer_name
  
  MARSHAL_TYPE  = :marshal
  YAML_TYPE     = :yaml
  JSON_TYPE     = :json
  MSGPACK_TYPE  = :msgpack
  
  MAX_OUT_BUFFER = 10

  # Raised when maxbuf exceeded.
  class OverflowError < StandardError; end

  @stream_class_map =
    Hash.new {raise ArgumentError, "unknown type: #{type.inspect}"}
  @mutex = Mutex.new

  class << self
    def new io, type: MARSHAL_TYPE, **opts
      if io.kind_of? ObjectStream
        raise ArgumentError,
          "given io is already an ObjectStream: #{io.inspect}"
      end
      stream_class_for(type).new io, **opts
    end

    def stream_class_for type
      cl = @stream_class_map[type]
      if cl.respond_to? :new
        cl
      else
        @mutex.synchronize do ## seems like overkill
          if cl.respond_to? :new
            cl
          else
            @stream_class_map[type] = cl.call
          end
        end
      end
    end
    
    def register_type type, &bl
      @stream_class_map[type] = bl
    end
  end
  
  def initialize io, **opts
    @io = io
    @object_buffer = nil
    @out_buffer = []
    @peer_name = "unknown"
    unexpect
  end
  
  def to_s
    "#<#{self.class} to #{peer_name}, io=#{io.inspect}>"
  end
  
  def expect cl = nil; end
  def unexpect; expect nil; end
  
  # raises EOFError
  def read
    if block_given?
      read_from_object_buffer {|obj| yield obj}
      read_from_stream {|obj| yield obj}
      return nil
    else
      read_one
    end
  end

  # read and return exactly one; blocking
  def read_one
    if @object_buffer and not @object_buffer.empty?
      return @object_buffer.shift
    end
    
    have_result = false
    result = nil
    until have_result
      read do |obj| # might not read enough bytes to yield an obj
        if have_result
          (@object_buffer||=[]) << obj
        else
          have_result = true
          result = obj
        end
      end
    end
    result
  end

  def read_from_object_buffer
    if @object_buffer and not @object_buffer.empty?
      @object_buffer.each {|obj| yield obj}
      @object_buffer.clear
    end
  end
  
  def write object
    write_to_buffer object
    flush_buffer
  end
  alias << write

  def write_to_object_buffer object=nil, &bl
    @out_buffer << (bl || object)
    flush_object_buffer if @out_buffer.size > MAX_OUT_BUFFER
    self
  end

  def flush_object_buffer
    @out_buffer.each do |object|
      object = object.call if object.kind_of? Proc
      write_to_stream object
    end
    @out_buffer.clear
    self
  end

  def write_to_buffer object
    flush_object_buffer
    write_to_stream object
    self
  end

  def flush_buffer
    self
  end

  # does not raise EOFError
  def each
    return to_enum unless block_given?
    read {|obj| yield obj} until eof
  rescue EOFError
  end
  
  def eof?
    (!@object_buffer || @object_buffer.empty?) && io.eof?
  end
  alias eof eof?

  # Call this if the most recent write was a #write_to_buffer without
  # a #flush_buffer. If you only use #write, there's no need to close
  # the stream in any special way.
  def close
    flush_object_buffer
    io.close
  end
  
  def closed?
    io.closed?
  end
  
  def accept
    io.accept
  end
  
  # Makes it possible to use stream in a select.
  def to_io
    io
  end
  
  class MarshalStream
    include ObjectStream
    
    ObjectStream.register_type MARSHAL_TYPE do
      self
    end
    
    def read_from_stream
      yield Marshal.load(io)
    end
    
    def write_to_stream object
      Marshal.dump(object, io)
      self
    end
  end
  
  class YamlStream
    include ObjectStream
    
    ObjectStream.register_type YAML_TYPE do
      require 'yaml'
      self
    end
    
    def read(*)
      unless block_given?
        raise "YamlStream does not support read without a block."
      end
      super
    end
      
    def read_from_stream
      YAML.load_stream(io) do |obj|
        yield obj
      end
    end
    
    def write_to_stream object
      YAML.dump(object, io)
      self
    end
  end
  
  class JsonStream
    include ObjectStream
    
    ObjectStream.register_type JSON_TYPE do
      require 'yajl'
      require 'yajl/json_gem'
      self
    end
    
    attr_accessor :chunk_size

    DEFAULT_CHUNK_SIZE = 2000

    def initialize io, chunk_size: DEFAULT_CHUNK_SIZE
      super
      @parser = Yajl::Parser.new
      @encoder = Yajl::Encoder.new
      @chunk_size = chunk_size
    end

    # class cl should define #to_json and cl.from_serialized; the block form
    # has the same effect, but avoids executing the code in the block in the
    # case when expect is a no-op (marshal and yaml).
    def expect cl = yield
      @expected_class = cl
    end
    
    def read_from_stream
      @parser.on_parse_complete = proc do |obj|
        yield @expected_class ? @expected_class.from_serialized(obj) : obj
      end
      @parser << io.readpartial(chunk_size)
    end
    
    def write_to_stream object
      @encoder.encode object, io
      self
    end
  end

  class MsgpackStream
    include ObjectStream
    
    ObjectStream.register_type MSGPACK_TYPE do
      require 'msgpack'
      self
    end
    
    attr_accessor :chunk_size
    attr_accessor :maxbuf

    DEFAULT_CHUNK_SIZE = 2000
    DEFAULT_MAXBUF = 4000
    
    def initialize io, chunk_size: DEFAULT_CHUNK_SIZE, maxbuf: DEFAULT_MAXBUF
      super
      @unpacker = MessagePack::Unpacker.new
        # don't specify io, so don't have to read all of io in one loop
      
      @packer = MessagePack::Packer.new(io)
      @chunk_size = chunk_size
      @maxbuf = maxbuf
      @consumers = []
    end

    # class cl should define #to_msgpack and cl.from_serialized; the block form
    # has the same effect, but avoids executing the code in the block in the
    # case when expect is a no-op (marshal and yaml).
    def expect cl = yield
      @expected_class = cl
    end
    
    def consume &bl
      @consumers << bl
    end

    def read_from_stream
      fill_buffer(chunk_size)
      checkbuf if maxbuf
      read_from_buffer do |obj|
        yield obj
      end
    end
    
    def fill_buffer n
      @unpacker.feed(io.readpartial(n))
    end

    def read_from_buffer
      @unpacker.each do |obj|
        try_consume(obj) or
          yield @expected_class ? @expected_class.from_serialized(obj) : obj
      end
    end

    def try_consume obj
      if bl = @consumers.shift
        bl[obj]
        true
      else
        false
      end
    end
    
    def checkbuf
      if maxbuf and @unpacker.buffer.size > maxbuf
        raise OverflowError,
          "Exceeded buffer limit by #{@unpacker.buffer.size - maxbuf} bytes."
      end
    end
    
    def write_to_stream object
      @packer.write(object).flush
      self
    end
    
    def write_to_buffer object
      flush_object_buffer
      @packer.write(object)
      self
    end
    
    def flush_buffer
      @packer.flush
      self
    end
  end
end
