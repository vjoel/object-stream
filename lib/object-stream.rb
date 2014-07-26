# Stream of objects, with any underlying IO: File, Pipe, Socket, StringIO.
# Stream is bidirectional if the IO is bidirectional.
#
# Serializes objects using any of several serializers: marshal, yaml, json,
# msgpack. Works with select/readpartial if the serializer supports it (msgpack
# and yajl do).
#
# ObjectStream supports three styles of iteration: Enumerable, blocking read,
# and yielding (non-blocking) read.
module ObjectStream
  include Enumerable

  VERSION = "0.6"

  # The IO through which the stream reads and writes serialized object data.
  attr_reader :io

  # Number of outgoing objects that can accumulate before the outbox is
  # serialized to the byte buffer (and possibly to the io).
  attr_reader :max_outbox

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

  # Raised when incoming data is unreadable.
  class StreamError < StandardError; end

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
  end

  def to_s
    "#<#{self.class} io=#{io.inspect}>"
  end

  # If no block given, behaves just the same as #read_one. If block given,
  # reads any available data and yields it to the block. This form is non-
  # blocking, if supported by the underlying serializer (such as msgpack).
  def read
    if block_given?
      read_from_inbox {|obj| yield obj}
      checked_read_from_stream {|obj| yield obj}
      return nil
    else
      read_one
    end
  end

  def checked_read_from_stream
    read_from_stream {|obj| yield obj}
  rescue IOError, SystemCallError, OverflowError
    raise
  rescue => ex
    raise StreamError, "unreadble stream: #{ex}"
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

  # Write the given objects to the stream, first flushing any objects in the
  # outbox. Flushes the underlying byte buffer afterwards.
  def write *objects
    write_to_buffer(*objects)
    flush_buffer
  end
  alias << write

  # Push the given object into the outbox, to be written later when the outbox
  # is flushed. If a block is given, it will be called when the outbox is
  # flushed, and its value will be written instead.
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

  def write_to_buffer *objects
    flush_outbox
    objects.each do |object|
      write_to_stream object
    end
    self
  end

  def flush_buffer
    self
  end

  # Iterate through the (rest of) the stream of objects. Does not raise
  # EOFError, but simply returns. All Enumerable and Enumerator methods are
  # available.
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

    # See the discussion in examples/symbolize-keys.rb.
    def initialize io, chunk_size: DEFAULT_CHUNK_SIZE, symbolize_keys: false
      super
      @parser = Yajl::Parser.new(symbolize_keys: symbolize_keys)
      @encoder = Yajl::Encoder.new
      @chunk_size = chunk_size
    end

    # Blocks only if no data available on io.
    def read_from_stream(&bl)
      @parser.on_parse_complete = bl
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

    # See the discussion in examples/symbolize-keys.rb.
    def initialize io, chunk_size: DEFAULT_CHUNK_SIZE, maxbuf: DEFAULT_MAXBUF,
          symbolize_keys: false
      super
      @unpacker = MessagePack::Unpacker.new(symbolize_keys: symbolize_keys)
        # don't specify io, so don't have to read all of io in one loop

      @packer = MessagePack::Packer.new(io)
      @chunk_size = chunk_size
      @maxbuf = maxbuf
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
        yield obj
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

    def write_to_buffer *objects
      flush_outbox
      objects.each do |object|
        @packer.write(object)
      end
      self
    end

    def flush_buffer
      @packer.flush
      self
    end
  end
end
