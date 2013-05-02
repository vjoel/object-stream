require 'object-stream'
require 'socket'

require 'minitest/autorun'

class TestObjectBuffer < MiniTest::Unit::TestCase
  attr_reader :s, :t
  
  def setup
    @s, @t = UNIXSocket.pair
  end
  
  def test_marshal
    do_test(ObjectStream::MARSHAL_TYPE)
  end
  
  def test_yaml
    assert_raises RuntimeError do
      # YamlStream does not support read without a block.
      do_test(ObjectStream::YAML_TYPE)
    end
  end
  
  def test_json
    do_test(ObjectStream::JSON_TYPE)
  end
  
  def test_msgpack
    do_test(ObjectStream::MSGPACK_TYPE)
  end
  
  def do_test type
    n = 200
    n_each = [n - 40, n/2].max
    
    th = Thread.new do
      src = ObjectStream.new(s, type: type)
      n.times do |i|
        src << [i]
      end
      src.close
    end

    dst = ObjectStream.new(t, type: type)
    i = 0
    begin
      loop do
        rand(5).times do
          assert_equal(i, dst.read[0])
          i+=1
        end

        dst.read do |obj|
          assert_equal(i, obj[0])
          i+=1
        end
        
        if i > n_each
          dst.each do |obj|
            assert_equal(i, obj[0])
            i+=1
          end
        end
      end
    rescue EOFError
    end
  end
end
