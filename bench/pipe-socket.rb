require 'benchmark'
require 'object-stream'
require 'socket'

def run(
    rd:       nil,
    wr:       nil,
    objects:  1..10,
    type:     ObjectStream::MSGPACK_TYPE)

  pid = fork do
    stream = ObjectStream.new(wr, type: type)
    objects.each do |object|
      stream << object
    end
  end
  wr.close

  stream = ObjectStream.new(rd, type: type)
  count = stream.inject(0) do |n, object|
    n + 1
  end
  raise unless count == objects.size
  stream.close

ensure
  Process.wait pid if pid
end

begin # warmup
  rd, wr = IO.pipe
  run rd: rd, wr: wr

  rd, wr = UNIXSocket.pair
  run rd: rd, wr: wr
end

tuples = (0...10_000).map {|i|
  [i, 42.42, true, "foo", {"bar" => "baz"}]
}

Benchmark.bm(10) do |bench|
  bench.report "pipe" do
    rd, wr = IO.pipe
    run rd: rd, wr: wr, objects: tuples
  end
  
  bench.report "socket" do
    rd, wr = UNIXSocket.pair
    run rd: rd, wr: wr, objects: tuples
  end
end
