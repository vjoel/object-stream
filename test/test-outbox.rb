require 'object-stream'
require 'stringio'

require 'minitest/autorun'

class TestOutbox < Minitest::Test
  attr_reader :sio

  def setup
    @sio = StringIO.new
  end

  def test_outbox_is_lazy
    stream = ObjectStream.new(sio, type: ObjectStream::MSGPACK_TYPE)
    stream.write_to_outbox "foo"
    sio.rewind
    assert_empty sio.read
  end

  def test_outbox_precedes
    stream = ObjectStream.new(sio, type: ObjectStream::MSGPACK_TYPE)
    n_foo = stream.max_outbox+10

    n_foo.times do |i|
      stream.write_to_outbox "foo#{i}"
    end
    stream.write "bar"
    sio.rewind

    stream = ObjectStream.new(sio, type: ObjectStream::MSGPACK_TYPE)
    items = stream.to_a
    assert_equal n_foo + 1, items.size
    assert_equal "bar", items.last
  end
end
