require 'object-stream-wrapper'
require 'stringio'

require 'minitest/autorun'

class TestExpect < Minitest::Test
  attr_reader :sio
  
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
    
    def to_a
      [@x, @y]
    end
    
    def to_json
      to_a.to_json
    end
    
    def self.from_serialized ary
      new *ary
    end
    
    def == other
      self.class == other.class and
        to_a == other.to_a
    end
  end
  
  class B < A
  end

  def setup
    @sio = StringIO.new
  end
  
  def test_expect
    objects = []
    20.times do |i|
      if rand < 0.5
        objects << "A" << A.new(i, i.to_s)
      else
        objects << "B" << B.new(i, i.to_s)
      end
    end
    
    stream = ObjectStreamWrapper.new(sio, type: ObjectStream::MSGPACK_TYPE)
    objects.each do |object|
      stream << object
    end
    
    sio.rewind
    stream = ObjectStreamWrapper.new(sio, type: ObjectStream::MSGPACK_TYPE)
    objects2 = []
    stream.read do |object|
      case object
      when "A"; stream.expect A
      when "B"; stream.expect B
      else stream.unexpect
      end
      objects2 << object
    end
    assert_equal objects, objects2
  end
end
