require 'rake'
require 'rake/testtask'

def version
  require 'object-stream'
  @version ||= ObjectStream::VERSION
end

prj = "object-stream"

desc "Run tests"
Rake::TestTask.new :test do |t|
  t.libs << "lib"
  t.libs << "ext"
  t.test_files = FileList["test/**/*.rb"]
end

desc "commit, tag, and push repo; build and push gem"
task :release do
  require 'tempfile'
  
  tag = "#{prj}-#{version}"

  sh "gem build #{prj}.gemspec"

  file = Tempfile.new "template"
  begin
    file.puts "release #{version}"
    file.close
    sh "git commit -a -v -t #{file.path}"
  ensure
    file.close unless file.closed?
    file.unlink
  end

  sh "git tag #{prj}-#{version}"
  sh "git push"
  sh "git push --tags"
  
  sh "gem push #{prj}-#{version}.gem"
end
