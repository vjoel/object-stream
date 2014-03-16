require 'object-stream'
require 'stringio'

require 'minitest/autorun'

module TestSymbolizeKeys
  attr_reader :sio, :stream
  
  BASIC_OBJECTS = [
    nil,
    true,
    false,
    "The quick brown fox jumped over the lazy dog's back.",
    [-5, "foo", [4]],
    {a: 1, b: 2},
    {top: [ {middle: [bottom: "turtle"]} ] }
  ]

  def type; self.class::TYPE; end
  def objects; BASIC_OBJECTS + self.class::OBJECTS; end

  def setup
    @sio = StringIO.new
    @stream = ObjectStream.new sio, type: type, symbolize_keys: true
  end
  
  def test_write_read
    objects.each do |obj|
      sio.rewind # do not need to clear stream's buffer (if any)
      sio.truncate 0
      stream.write obj

      sio.rewind
      dump = sio.read
      sio.rewind

      stream.read do |obj2|
        assert_equal(obj, obj2, "dump is #{dump.inspect}")
      end
    end
  end
end

class TestSymbolizeKeysJson < Minitest::Test
  include TestSymbolizeKeys

  TYPE = ObjectStream::JSON_TYPE
  OBJECTS = []
end

class TestSymbolizeKeysMsgpack < Minitest::Test
  include TestSymbolizeKeys

  TYPE = ObjectStream::MSGPACK_TYPE
  OBJECTS = []
end
