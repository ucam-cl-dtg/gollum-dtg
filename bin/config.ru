#!/usr/bin/env ruby

$:.unshift File.join(File.dirname(__FILE__), *%w[.. lib])

help = <<HELP
Gollum is a multi-format Wiki Engine/API/Frontend.

Basic Command Line Usage:
  gollum [OPTIONS] [PATH]

        PATH                         The path to the Gollum repository (default .).

Options:
HELP

require 'optparse'
require 'rubygems'
require 'gollum'
require 'gitolite-dtg'

exec = {}
options = { 'port' => 3000, 'bind' => '0.0.0.0' }
wiki_options = {}

git_repos_path = '/srv/git/repositories' # CHANGE THIS TO POINT TO YOUR GITOLITE BASE REPO PATH
wiki_repos_pattern = 'wiki/'
wikis_breadcrumb_url = 'http://localhost/list'

ga_repo = Gitolite::Dtg::GitoliteAdmin.new(File.join(git_repos_path , "gitolite-admin.git"))
repos = ga_repo.config.get_repos(wiki_repos_pattern)
repos_path = repos.map { |s| s[wiki_repos_pattern.length,s.length] }

print "Here we go!"
Precious::App.set(:repos_path, git_repos_path)
Precious::App.set(:gitolite_repo, ga_repo)
Precious::App.set(:wiki_repos, repos)
Precious::App.set(:wiki_repos_path, repos_path)
Precious::App.set(:wiki_repos_pattern, wiki_repos_pattern)
Precious::App.set(:wiki_bcrumb, wikis_breadcrumb_url)

opts = OptionParser.new do |opts|
  opts.banner = help

  opts.on("--port [PORT]", "Bind port (default 4567).") do |port|
    options['port'] = port.to_i
  end

  opts.on("--host [HOST]", "Hostname or IP address to listen on (default 0.0.0.0).") do |host|
    options['bind'] = host
  end

  opts.on("--version", "Display current version.") do
    puts "Gollum " + Gollum::VERSION
    exit 0
  end

  opts.on("--config [CONFIG]", "Path to additional configuration file") do |config|
    options['config'] = config
  end

  opts.on("--irb", "Start an irb process with gollum loaded for the current wiki.") do
    options['irb'] = true
  end

  opts.on("--page-file-dir [PATH]", "Specify the sub directory for all page files (default: repository root).") do |path|
    wiki_options[:page_file_dir] = path
  end

  opts.on("--ref [REF]", "Specify the repository ref to use (default: master).") do |ref|
    wiki_options[:ref] = ref
  end
end

# Read command line options into `options` hash
begin
  opts.parse!
rescue OptionParser::InvalidOption
  puts "gollum: #{$!.message}"
  puts "gollum: try 'gollum --help' for more information"
  exit
end

gollum_path = "/home/calucian/wiki" || Dir.pwd

if options['irb']
  require 'irb'
  # http://jameskilton.com/2009/04/02/embedding-irb-into-your-ruby-application/
  module IRB # :nodoc:
    def self.start_session(binding)
      unless @__initialized
        args = ARGV
        ARGV.replace(ARGV.dup)
        IRB.setup(nil)
        ARGV.replace(args)
        @__initialized = true
      end

      ws  = WorkSpace.new(binding)
      irb = Irb.new(ws)

      @CONF[:IRB_RC].call(irb.context) if @CONF[:IRB_RC]
      @CONF[:MAIN_CONTEXT] = irb.context

      catch(:IRB_EXIT) do
        irb.eval_input
      end
    end
  end

  begin
    wiki = Gollum::Wiki.new(gollum_path, wiki_options)
    if !wiki.exist? then raise Grit::InvalidGitRepositoryError end
    puts "Loaded Gollum wiki at #{File.expand_path(gollum_path).inspect}."
    puts
    puts %(    page = wiki.page('page-name'))
    puts %(    # => <Gollum::Page>)
    puts
    puts %(    page.raw_data)
    puts %(    # => "# My wiki page")
    puts
    puts %(    page.formatted_data)
    puts %(    # => "<h1>My wiki page</h1>")
    puts
    puts "Check out the Gollum README for more."
    IRB.start_session(binding)
  rescue Grit::InvalidGitRepositoryError, Grit::NoSuchPathError
    puts "Invalid Gollum wiki at #{File.expand_path(gollum_path).inspect}"
    exit 0
  end
else
  require 'gollum/frontend/app'



  Precious::App.set(:wiki_options, wiki_options)


  if cfg = options['config']
    # If the path begins with a '/' it will be considered an absolute path,
    # otherwise it will be relative to the CWD
    cfg = File.join(Dir.getwd, cfg) unless cfg.slice(0) == File::SEPARATOR
    require cfg
  end

  Precious::App.run!(options)
end
