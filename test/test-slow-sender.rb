require 'object-stream'
require 'socket'
require 'stringio'

require 'minitest/autorun'

class TestSlowSender < Minitest::Test
  attr_reader :s, :t
  
  def setup
    @s, @t = UNIXSocket.pair
  end
  
  def test_marshal
    assert_equal(:block, get_test_result(ObjectStream::MARSHAL_TYPE))
  end
  
  def test_yaml
    assert_equal(:block, get_test_result(ObjectStream::YAML_TYPE))
  end
  
  def test_json
    assert_equal(:noblock, get_test_result(ObjectStream::JSON_TYPE))
  end
  
  def test_msgpack
    assert_equal(:noblock, get_test_result(ObjectStream::MSGPACK_TYPE))
  end
  
  def get_test_result type
    pid = fork do
      sio = StringIO.new
      stream = ObjectStream.new(sio, type: type)
      10.times do |i|
        stream << "foo bar #{i}"
      end

      sio.rewind
      data = sio.read
      pos = data.index "bar 5"
      raise unless pos < data.size - 10 # assume strings not munged
      s.write data[0...pos]
      sleep 0.1
      s.write data[pos...pos+1]
      sleep 0.1
      s.write data[pos+1...pos+2]
      sleep 0.1
      s.write data[pos+2..-1]
    end

    s.close
    stream = ObjectStream.new(t, type: type)

    select_count = 0
    empty_read_count = 0
    until stream.eof?
      select_count += 1
      select([stream])

      obj_count = 0
      stream.read do |obj|
        obj_count += 1
      end
      if obj_count == 0
        empty_read_count += 1
      end
    end

    stream.close
    if select_count > 1 and empty_read_count > 0
      :noblock
    else
      :block
    end

  ensure
    Process.wait pid if pid
  end
end
