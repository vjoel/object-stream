require 'object-stream'
require 'stringio'

require 'minitest/autorun'

class TestMaxbuf < MiniTest::Unit::TestCase
  attr_reader :sio, :stream
  
  def setup
    @sio = StringIO.new
  end
  
  def test_maxbuf
    stream = ObjectStream.new(sio, type: ObjectStream::MSGPACK_TYPE)
    stream << "a"*20
    sio.rewind
    stream = ObjectStream.new(sio, type: ObjectStream::MSGPACK_TYPE, maxbuf: 20)
    assert_raises(ObjectStream::OverflowError) do
      stream.to_a
    end
  end
end
