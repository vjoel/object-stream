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
  
  def test_batch_write
    a = ["a", "b", "c"]
    stream.write *a
    sio.rewind
    dump = sio.read
    sio.rewind
    assert_equal(a, stream.to_a, "dump is #{dump.inspect}")
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

  def test_break
    a = (1..10).to_a
    a.each do |i|
      stream.write [i]
    end
  
    sio.rewind
    
    a2 = []
    stream.each do |object|
      i = object[0]
      a2 << i
      break if i == 5
    end
    
    stream.each do |object|
      i = object[0]
      a2 << i
    end

    case type
    when ObjectStream::MARSHAL_TYPE
      assert_equal(a, a2)
    else
      assert_equal(a[0..4], a2) # fixable?
    end
  end

  def test_enum
    objects.each do |obj|
      stream.write obj
    end

    sio.rewind

    enum = stream.each
    assert_equal(objects, enum.to_a)
  end
  
  def test_read_without_block
    return if type == ObjectStream::YAML_TYPE

    n = 100
    n.times do |i|
      stream << [i]
    end

    stream.io.rewind

    count = 0
    until stream.eof?
      obj = stream.read
      assert_equal [count], obj
      count += 1
    end
    assert_equal n, count
  end
end

class TestBasicMarshal < Minitest::Test
  include TestBasic

  TYPE = ObjectStream::MARSHAL_TYPE
  OBJECTS = ADVANCED_OBJECTS + RUBY_OBJECTS
end

class TestBasicYaml < Minitest::Test
  include TestBasic

  TYPE = ObjectStream::YAML_TYPE
  OBJECTS = ADVANCED_OBJECTS + RUBY_OBJECTS
end

class TestBasicJson < Minitest::Test
  include TestBasic

  TYPE = ObjectStream::JSON_TYPE
  OBJECTS = [] # poor json!
end

class TestBasicMsgpack < Minitest::Test
  include TestBasic

  TYPE = ObjectStream::MSGPACK_TYPE
  OBJECTS = ADVANCED_OBJECTS
end
