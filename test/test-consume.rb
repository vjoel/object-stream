require 'object-stream'
require 'stringio'

require 'minitest/autorun'

class TestExpect < MiniTest::Unit::TestCase
  attr_reader :sio

  def setup
    @sio = StringIO.new
  end
  
  def test_consume
    n_total = 10
    n_consumed = 5
    
    objects = (0...n_total).map {|i| [i]}
    
    stream = ObjectStream.new(sio, type: ObjectStream::MSGPACK_TYPE)
    objects.each do |object|
      stream << object
    end
    
    sio.rewind
    stream = ObjectStream.new(sio, type: ObjectStream::MSGPACK_TYPE)
    
    count = 0
    
    n_consumed.times do |i|
      stream.consume do |a|
        assert_equal(i, a[0])
        count += 1
      end
    end
    
    assert_equal(0, sio.pos)
    
    stream.each_with_index do |a, i|
      assert_equal i + n_consumed, a[0]
      count += 1
    end
    
    assert_equal(n_total, count)
  end
end
