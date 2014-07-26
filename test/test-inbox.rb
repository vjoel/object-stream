require 'object-stream'
require 'socket'

require 'minitest/autorun'

class TestInbox < Minitest::Test
  attr_reader :s, :t

  def setup
    @s, @t = UNIXSocket.pair
  end

  def test_marshal
    do_test(ObjectStream::MARSHAL_TYPE)
  end

  def test_yaml
    do_test(ObjectStream::YAML_TYPE)
  end

  def test_json
    do_test(ObjectStream::JSON_TYPE)
  end

  def test_msgpack
    do_test(ObjectStream::MSGPACK_TYPE)
  end

  def do_test type
    n = 200
    Thread.new do
      src = ObjectStream.new(s, type: type)
      n.times do |i|
        src << [i]
      end
      src.close
    end

    dst = ObjectStream.new(t, type: type)
    i = 0

    begin
      rand(5).times do
        assert_equal(i, dst.read[0])
        i+=1
      end
    rescue EOFError
    end

    begin
      dst.read do |obj|
        assert_equal(i, obj[0])
        i+=1
      end
    rescue EOFError
    end

    dst.each do |obj|
      assert_equal(i, obj[0])
      i+=1
    end

    assert_equal n, i
  end
end
