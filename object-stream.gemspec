Gem::Specification.new do |s|
  s.name = "object-stream"
  s.version = "0.1"

  s.required_rubygems_version = Gem::Requirement.new(">= 0")
  s.authors = ["Joel VanderWerf"]
  s.date = "2013-07-12"
  s.description = "Stream objects over IO using Marshal, JSON, YAML, or Msgpack."
  s.email = "vjoel@users.sourceforge.net"
  s.extra_rdoc_files = ["README.md", "COPYING"]
  s.files = Dir[
    "README.md", "COPYING", "Rakefile",
    "lib/**/*.rb",
    "bench/**/*.rb",
    "examples/**/*.rb",
    "test/**/*.rb"
  ]
  s.test_files = Dir["test/*.rb"]
  s.homepage = "https://github.com/vjoel/object-stream"
  s.license = "BSD"
  s.rdoc_options = ["--quiet", "--line-numbers", "--inline-source", "--title", "object-stream", "--main", "README.md"]
  s.require_paths = ["lib"]
  s.summary = "Stream objects over IO using Marshal, JSON, YAML, or Msgpack"

  s.add_dependency 'msgpack'
  s.add_dependency 'yajl'
end
