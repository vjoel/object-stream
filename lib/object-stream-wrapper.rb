require 'object-stream'

# Utility wrapper for basic ObjectStream class. Adds three groups of
# functionality:
#
#  * peer_name
#
#  * expect
#
#  * consume
#
class ObjectStreamWrapper
  include Enumerable

  # Not set by this library, but available for users to keep track of
  # the peer in a symbolic, application-specific manner. See funl for
  # an example.
  attr_accessor :peer_name

  def initialize *args, **opts
    @stream = ObjectStream.new(*args, **opts)
    @peer_name = "unknown"
    @expected_class = nil
    @consumers = []
    unexpect
  end

  def to_s
    "#<Wrapped #{@stream.class} to #{peer_name}, io=#{@stream.inspect}>"
  end

  # Set the stream state so that subsequent objects returned by read will be
  # instances of a custom class +cl+. Does not affect #consume.
  # Class +cl+ should define cl.from_serialized, plus #to_json, #to_msgpack,
  # etc. as needed by the underlying serialization library.
  def expect cl
    @expected_class = cl
  end

  # Turn off the custom class instantiation of #expect.
  def unexpect; expect nil; end

  # The block is appended to a queue of procs that are called for the
  # subsequently read objects, instead of iterating over or returning them.
  # Helps with handshake protocols. Not affected by #expect.
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

  def convert_to_expected obj
    if @expected_class and not obj.kind_of? @expected_class
      @expected_class.from_serialized(obj)
    else
      obj
    end
  rescue => ex
    raise StreamError, "cannot convert to expected class: #{obj.inspect}: #{ex}"
  end
  private :convert_to_expected

  def read
    if block_given?
      @stream.read do |obj|
        try_consume(obj) or yield convert_to_expected(obj)
      end
      return nil
    else
      begin
        obj = @stream.read
      end while try_consume(obj)
      convert_to_expected(obj)
    end
  end

  def each
    return to_enum unless block_given?
    read {|obj| yield obj} until eof
  rescue EOFError
  end

  def write *objects
    @stream.write(*objects)
  end
  alias << write

  def write_to_outbox *args, &bl
    @stream.write_to_outbox(*args, &bl)
  end

  def eof?
    @stream.eof?
  end
  alias eof eof?

  def close
    @stream.close
  end

  def closed?
    @stream.closed?
  end

  def to_io
    @stream.to_io
  end
end
