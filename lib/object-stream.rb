# Stream of objects, with any underlying IO: File, Pipe, Socket, StringIO.
# Stream is bidirectional if the IO is bidirectional. Serializes objects using
# any of several serializers: marshal, yaml, json, msgpack. Works with
# select/readpartial if the serializer supports it (msgpack and yajl do).
# ObjectStream supports three styles of iteration: Enumerable, blocking read,
# and yielding read. The #expect method is a way to instantiate custom classes
# in cases (msgpack, json) which do not support it natively. The #consume
# method helps with handshake protocols.
module ObjectStream
  include Enumerable
  
  # The IO through which the stream reads and writes serialized object data.
  attr_reader :io
  
  # Number of outgoing objects that can accumulate before the outbox is
  # serialized to the character buffer (and possibly to the io).
  attr_reader :max_outbox
  
  # Not set by this library, but available for users to keep track of
  # the peer in a symbolic, application-specific manner. See funl for
  # an example.
  attr_accessor :peer_name
  
  MARSHAL_TYPE  = "marshal".freeze
  YAML_TYPE     = "yaml".freeze
  JSON_TYPE     = "json".freeze
  MSGPACK_TYPE  = "msgpack".freeze
  
  TYPES = [
    MARSHAL_TYPE, YAML_TYPE, JSON_TYPE, MSGPACK_TYPE
  ]

  DEFAULT_MAX_OUTBOX = 10

  # Raised when maxbuf exceeded.
  class OverflowError < StandardError; end

  @stream_class_map =
    Hash.new {|h,type| raise ArgumentError, "unknown type: #{type.inspect}"}
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
      return cl if cl.respond_to? :new

      # Protect against race condition in msgpack and yajl extension
      # initialization (bug #8374).
      @mutex.synchronize do
        return cl if cl.respond_to? :new
        @stream_class_map[type] = cl.call
      end
    end
    
    def register_type type, &bl
      @stream_class_map[type] = bl
    end
  end
  
  def initialize io, max_outbox: DEFAULT_MAX_OUTBOX, **opts
    @io = io
    @max_outbox = max_outbox
    @inbox = nil
    @outbox = []
    @peer_name = "unknown"
    @consumers = []
    unexpect
  end
  
  def to_s
    "#<#{self.class} to #{peer_name}, io=#{io.inspect}>"
  end
  
  # Set the stream state so that subsequent objects will be instances of a
  # custom class +cl+, assuming that +cl+ supports certain methods. See the
  # comments for specific serializer expect methods. Not needed for classes that
  # serialize the class of an object.
  def expect cl = nil; end
  
  # Turn off the custom class instantiation of #expect.
  def unexpect; expect nil; end

  # The block is appended to a queue of procs that are called for the
  # subsequently read objects, instead of iterating over or returning them.
  def consume &bl
    @consumers << bl
  end

  def try_consume obj
    if bl = @consumers.shift
      bl[obj]
      true
    else
      false
    end
  end
  private :try_consume

  # If no block given, behaves just the same as #read_one. If block given,
  # reads any available data and yields it to the block. This form is non-
  # blocking, if supported by the underlying serializer (such as msgpack).
  def read
    if block_given?
      read_from_inbox {|obj| try_consume(obj) or yield obj}
      read_from_stream {|obj| try_consume(obj) or yield obj}
      return nil
    else
      read_one
    end
  end

  # Read one object from the stream, blocking if necessary. Returns the object.
  # Raises EOFError at the end of the stream.
  def read_one
    if @inbox and not @inbox.empty?
      return @inbox.shift
    end
    
    have_result = false
    result = nil
    until have_result
      read do |obj| # might not read enough bytes to yield an obj
        if have_result
          (@inbox||=[]) << obj
        else
          have_result = true
          result = obj
        end
      end
    end
    result
  end

  def read_from_inbox
    if @inbox and not @inbox.empty?
      @inbox.each {|obj| yield obj}
      @inbox.clear
    end
  end
  private :read_from_inbox
  
  def write object
    write_to_buffer object
    flush_buffer
  end
  alias << write

  def write_to_outbox object=nil, &bl
    @outbox << (bl || object)
    flush_outbox if @outbox.size > max_outbox
    self
  end

  def flush_outbox
    @outbox.each do |object|
      object = object.call if object.kind_of? Proc
      write_to_stream object
    end
    @outbox.clear
    self
  end

  def write_to_buffer object
    flush_outbox
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
    (!@inbox || @inbox.empty?) && io.eof?
  end
  alias eof eof?

  # Call this if the most recent write was a #write_to_buffer without
  # a #flush_buffer. If you only use #write, there's no need to close
  # the stream in any special way.
  def close
    flush_outbox
    io.close
  end
  
  def closed?
    io.closed?
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

    # Class +cl+ should define #to_json and cl.from_serialized; the block form
    # has the same effect, but avoids executing the code in the block in the
    # case when expect is a no-op (marshal and yaml).
    def expect cl = yield
      @expected_class = cl
    end
    
    # Blocks only if no data available on io.
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
    end

    # Class +cl+ should define #to_msgpack and cl.from_serialized; the block
    # form has the same effect, but avoids executing the code in the block in
    # the case when expect is a no-op (marshal and yaml).
    def expect cl = yield
      @expected_class = cl
    end
    
    # Blocks only if no data available on io.
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
        yield @expected_class ? @expected_class.from_serialized(obj) : obj
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
      flush_outbox
      @packer.write(object)
      self
    end
    
    def flush_buffer
      @packer.flush
      self
    end
  end
end
