require 'object-stream'
require 'stringio'

require 'minitest/autorun'

module TestBasic
  attr_reader :sio, :stream
  
  # supported by all types
  BASIC_OBJECTS = [
    nil,
    true,
    false,
    "The quick brown fox jumped over the lazy dog's back.",
    [-5, "foo", [4]],
    {"a" => 1, "b" => 2}
  ]

  ADVANCED_OBJECTS = [
    12,
    2**40 + 123,
    3.45,
    { 1 => 2 },
    { ["a"] => 3 },
    { {"b" => 5} => 6 }
  ]
  
  class Custom
    attr_reader :x, :y
    def initialize x, y
      @x, @y = x, y
    end
    def ==(other)
      @x == other.x
      @y == other.y # just enough to make test pass
    end
  end
  
  RUBY_OBJECTS = [
    :foo,
    {:foo => :bar},
    String,
    File,
    Custom.new(1,2)
  ]
  
  def type; self.class::TYPE; end
  def objects; BASIC_OBJECTS + self.class::OBJECTS; end
  
  def setup
    @sio = StringIO.new
    @stream = ObjectStream.new sio, type: type
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
  
  def test_each
    objects.each do |obj|
      stream.write obj
    end
  
    sio.rewind
    dump = sio.read
    sio.rewind
    
    assert_equal(objects, stream.to_a, # <-- #each called by #to_a
      "dump is #{dump.inspect}")
  end
end

class TestBasicMarshal < MiniTest::Unit::TestCase
  include TestBasic

  TYPE = ObjectStream::MARSHAL_TYPE
  OBJECTS = ADVANCED_OBJECTS + RUBY_OBJECTS
end

class TestBasicYaml < MiniTest::Unit::TestCase
  include TestBasic

  TYPE = ObjectStream::YAML_TYPE
  OBJECTS = ADVANCED_OBJECTS + RUBY_OBJECTS
end

class TestBasicJson < MiniTest::Unit::TestCase
  include TestBasic

  TYPE = ObjectStream::JSON_TYPE
  OBJECTS = [] # poor json!
end

class TestBasicMsgpack < MiniTest::Unit::TestCase
  include TestBasic

  TYPE = ObjectStream::MSGPACK_TYPE
  OBJECTS = ADVANCED_OBJECTS
end
