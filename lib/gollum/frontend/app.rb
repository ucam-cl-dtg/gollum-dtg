require 'cgi'
require 'gollum/frontend/raven.rb'
require 'sinatra'
require 'gollum'
require 'mustache/sinatra'
require 'useragent'
require 'stringex'
require 'gitolite-dtg'

require 'gollum/frontend/views/layout'
require 'gollum/frontend/views/editable'
require 'gollum/frontend/views/has_page'

require File.expand_path '../helpers', __FILE__

# Fix to_url
class String
  alias :upstream_to_url :to_url
  # _Header => header which causes errors
  def to_url
    return nil if self.nil?
    return self if ['_Header', '_Footer', '_Sidebar'].include? self
    upstream_to_url
  end
end

# Run the frontend, based on Sinatra
#
# There are a number of wiki options that can be set for the frontend
#
# Example
# require 'gollum/frontend/app'
# Precious::App.set(:wiki_options, {
#     :universal_toc => false,
# }
#
# See the wiki.rb file for more details on wiki options
module Precious
  class App < Sinatra::Base
    register Mustache::Sinatra
    include Precious::Helpers

    dir = File.dirname(File.expand_path(__FILE__))
    #enable :sessions

    use Rack::Session::Cookie, :key => 'rack.session', :expire_after => 2592000 # In seconds

    # Detect unsupported browsers.
    Browser = Struct.new(:browser, :version)

    @@min_ua = [
        Browser.new('Internet Explorer', '10.0'),
        Browser.new('Chrome', '7.0'),
        Browser.new('Firefox', '4.0'),
    ]

    def supported_useragent?(user_agent)
      ua = UserAgent.parse(user_agent)
      @@min_ua.detect {|min| ua >= min }
    end

    # We want to serve public assets for now
    set :public_folder, "#{dir}/public/gollum"
    set :static,         true
    set :default_markup, :markdown

    set :mustache, {
      # Tell mustache where the Views constant lives
      :namespace => Precious,

      # Mustache templates live here
      :templates => "#{dir}/templates",

      # Tell mustache where the views are
      :views => "#{dir}/views"
    }

    # Sinatra error handling
    configure :development, :staging do
      enable :show_exceptions, :dump_errors
      disable :raise_errors, :clean_trace
    end

    configure :test do
      enable :logging, :raise_errors, :dump_errors
    end
    
    helpers do
  	  def protected!(rn, rpath, requested_access)
    		auth_rez = authorized(rn, rpath, requested_access)
        if auth_rez == 0
    			raven = Raven.new
    			raven.return_url = request.base_url + '/callback'
    			raven.description = 'DTG Gollum Wiki'
    			
    			message = 'the DTG Wiki page you are trying to access requires authorization'
    			if(session['principal']==nil)
    				raven_req_url = raven.get_raven_request(session, message, 'yes')
    			else
    				raven_req_url = raven.get_raven_request(session, message, '')
    			end
    			session['redirect-url'] = request.url
    			session['raven'] = raven

    			redirect raven_req_url
        elsif auth_rez == 2
            @title = "Access Denied"
            @message = "The access to this page is restricted. User "+session['principal']+" does not have sufficient permissions."
            halt mustache :error
    		end
  	  end

  	  def authorized(rn, rpath, requested_access)
        is_login = 0
    		if(Raven::check_session(session,'no') != nil)
    			@loggedin = true
    		  @username = session['principal']
    			is_login = 1
    		else
    			@loggedin = false
    			@username = nil
    			is_login = 0
    		end

        if(rn == nil && rpath == nil)
          return 1
        end

        if(rpath == nil)
          rpath = '/'
        end
  		  ga_repo = settings.gitolite_repo
    		if(is_login == 1)
          if(rn == nil)
            return 1
          end
          auth_ok =  ga_repo.authorize(File.join(settings.wiki_repos_pattern, rn), @username, rpath, requested_access)
          auth_ok ? 1 : 2
    		else
          if(rn == nil)
            return 0
          end
    			auth_ok =  ga_repo.authorize(File.join(settings.wiki_repos_pattern, rn), nil, rpath, requested_access)
          auth_ok ? 1 : 0
    		end
  	  end
    end

    # path is set to name if path is nil.
    #   if path is 'a/b' and a and b are dirs, then
    #   path must have a trailing slash 'a/b/' or
    #   extract_path will trim path to 'a'
    # name, path, version
    def wiki_page(repo_name, name, path = nil, version = nil, exact = true)
      path = name if path.nil?
      name = extract_name(name)
      path = extract_path(path)
      path = '/' if exact && path.nil?

      opt  = settings.wiki_options.merge({ :base_path => File.join(@base_url,repo_name) })
      wiki = wiki_new(File.join(settings.repos_path,settings.wiki_repos_pattern,repo_name + '.git'), opt)

      OpenStruct.new(:wiki => wiki, :page => wiki.paged(name, path, exact, version),
                     :name => name, :path => path)
    end

    def wiki_new(gollum_path, opt)
      Gollum::Wiki.new(gollum_path, opt)
    end

    def show_page_or_file(repo_name, fullpath)
      name         = extract_name(fullpath)
      path         = extract_path(fullpath)
      opt          = settings.wiki_options.merge({ :base_path => File.join(@base_url,repo_name) })
      wiki         = wiki_new(File.join(settings.repos_path,settings.wiki_repos_pattern,repo_name + '.git'), opt)

      path = '/' if path.nil?

      if page = wiki.paged(name, path, exact = true)
        @page = page
        @name = name
        @editable = true
        @repo = repo_name
        @content = page.formatted_data
        @toc_content = wiki.universal_toc ? @page.toc_data : nil
        @mathjax = wiki.mathjax
        mustache :page
      elsif file = wiki.file(fullpath)
        content_type file.mime_type
        file.raw_data
      else
        page_path = [path, name].compact.join('/')
        redirect to("/"+repo_name+"/create/#{clean_url(encodeURIComponent(page_path))}")
      end
    end

    def update_wiki_page(wiki, page, content, commit, name = nil, format = nil)
      return if !page ||
        ((!content || page.raw_data == content) && page.format == format)
      name    ||= page.name
      format    = (format || page.format).to_sym
      content ||= page.raw_data
      wiki.update_page(page, name, format, content.to_s, commit)
    end


    ####
    ##
    ## Define Routes 
    ##
    ####

  	get '/login' do
  	    protected!(nil, "/", 'R')
  	    redirect '/'
      end
      
    get '/logout' do
       	session['principal'] = nil
       	session['gollum.author'] = nil
    	@loggedin=false
    	redirect '/'
    end
    
    get '/callback' do
    	raven = session['raven']
      if(raven != nil)
        rc = raven.check_response_from_raven(params,session,'no')
        if rc == 200
          @loggedin = true
          @username = session['principal']
          gollum_author = { :name => @username, :email => @username+'@cam.ac.uk' }
          session['gollum.author'] = gollum_author
          redirect session['redirect-url']
        else
          @message = "<p>Raven authentication failed (error code " + rc.to_s + "): "
          rmsg = "<p>Go back to the <a href=\"list\">wiki list</a> and try again</p>"
          if    rc == 520 
            @message+="the server uses a different version of the authentication protocol.</p>"+rmsg
          elsif rc == 570
            @message+="authentication was done for a different URL than the one you are trying to access. This is probabily an application bug, please report it.</p>"+rmsg
          elsif rc == 540
            @message+="something's fishy (raven reported that no login interraction took place). Please report the error.</p>"
          elsif rc == 410
            @message="Your Raven authentication was unsuccessful.</p>"+rmsg
          elsif rc == 550
            @loggedin=false
            redirect '/login' 
            # @message+="your raven ticket expired.</p><p>Please <a href=\"login\">login</a> again.</p>"
          else            
            @message+="unknown reason, please report the bug and mention the error code.</p>"+rmsg
          end
          session['principal'] = nil
          session['gollum.author'] = nil
          @loggedin=false
          mustache :error
        end
      else
        redirect '/login'
      end
    end

    before do
      @base_url = url('/', false).chomp('/')
      @repo = @base_url
      @wiki_bcrumb = settings.wiki_bcrumb
      settings.wiki_options.merge!({ :base_path => @base_url }) unless settings.wiki_options.has_key? :base_path
    end

    get '/' do
      redirect File.join(settings.wiki_options[:page_file_dir].to_s,settings.wiki_options[:base_path].to_s, 'list')
    end

    get '/list' do
    protected!(nil, nil, 'R')
      settings.gitolite_repo.reload!
      repos = settings.gitolite_repo.config.get_repos(settings.wiki_repos_pattern)
      repos_path = repos.map { |s| s[settings.wiki_repos_pattern.length,s.length] }
      @results = repos_path
      mustache :wiki_list
    end

    get '/:repo/data/*' do
    protected!(params[:repo], params[:splat].first, 'R')
      if page = wiki_page(params[:repo], params[:splat].first).page
        page.raw_data
      end
    end

    get '/:repo/edit/*' do
      protected!(params[:repo], params[:splat].first, 'W')
      wikip = wiki_page(params[:repo], params[:splat].first)
      @name = wikip.name
      @path = wikip.path
      wiki = wikip.wiki
      if page = wikip.page
        if wiki.live_preview && page.format.to_s.include?('markdown') && supported_useragent?(request.user_agent)
          live_preview_url = '/'+params[:repo]+'/livepreview/index.html?page=' + encodeURIComponent(@name)
          if @path
            live_preview_url << '&path=' + encodeURIComponent(@path)
          end
          redirect to(live_preview_url)
        else
          @page = page
          @page.version = wiki.repo.log(wiki.ref, @page.path).first
          @repo = params[:repo]
          raw_data = page.raw_data
          @content = raw_data.respond_to?(:force_encoding) ? raw_data.force_encoding('UTF-8') : raw_data
          mustache :edit
        end
      else
        redirect to("/"+params[:repo]+"/create/#{encodeURIComponent(@name)}")
      end
    end

   
    get '/:repo/replay/*/*' do
      wikip = wiki_page(params[:repo], params[:splat].first)
      @name = wikip.name
      @path = wikip.path
      wiki = wikip.wiki
      file = File.open(params[:repo] + "_" + params[:splat][1] + ".json", "r")
      replayActions = file.read
      
      if page = wikip.page
        @page = page
        @page.version = wiki.repo.log(wiki.ref, @page.path).first
        @repo = params[:repo]
        raw_data = page.raw_data
        @content = raw_data.respond_to?(:force_encoding) ? raw_data.force_encoding('UTF-8') : raw_data
        @livewritingActions = replayActions
        @livewriting_flag = true
        mustache :edit
      else
        redirect to("/"+params[:repo]+"/create/#{encodeURIComponent(@name)}")
      end
    end

    
    post '/:repo/edit/*' do
    protected!(params[:repo], params[:splat].first, 'W')
      path      = '/' + clean_url(sanitize_empty_params(params[:path])).to_s
      page_name = CGI.unescape(params[:page])
      opt       = settings.wiki_options.merge({ :base_path => File.join(@base_url,params[:repo]) })
      wiki      = wiki_new(File.join(settings.repos_path,settings.wiki_repos_pattern,params[:repo] + '.git'), opt)
      page      = wiki.paged(page_name, path, exact = true)
      return if page.nil?
      rename    = params[:rename].to_url if params[:rename]
      name      = rename || page.name
      committer = Gollum::Committer.new(wiki, commit_message)
      commit    = {:committer => committer}

      update_wiki_page(wiki, page, params[:content], commit, name, params[:format])
      update_wiki_page(wiki, page.header,  params[:header],  commit) if params[:header]
      update_wiki_page(wiki, page.footer,  params[:footer],  commit) if params[:footer]
      update_wiki_page(wiki, page.sidebar, params[:sidebar], commit) if params[:sidebar]
      version = committer.commit
      File.open(params[:repo] + "_" + version + ".json", "w") do |file|
        file.write params[:livewritingActions]
      end

      page = wiki.page(rename) if rename

      redirect to("/"+params[:repo]+"/#{page.escaped_url_path}") unless page.nil?
    end

    get '/:repo/delete/*' do
    protected!(params[:repo], params[:splat].first, 'W')
      wikip = wiki_page(params[:repo], params[:splat].first)
      name = wikip.name
      wiki = wikip.wiki
      page = wikip.page
      wiki.delete_page(page, { :message => "Destroyed #{name} (#{page.format})" })

      redirect to('/'+params[:repo])
    end

    get '/:repo/create/*' do
    protected!(params[:repo], params[:splat].first, 'W')
      wikip = wiki_page(params[:repo], params[:splat].first.gsub('+', '-'))
      @name = wikip.name.to_url
      @path = wikip.path
      @repo = params[:repo]

      page = wikip.page
      if page
        redirect to("/"+params[:repo]+"/#{page.escaped_url_path}")
      else
        mustache :create
      end
    end

    post '/:repo/create' do
      protected!(params[:repo], params[:path], 'W')
      name         = params[:page].to_url
      path         = sanitize_empty_params(params[:path])
      path = '' if path.nil?
      format       = params[:format].intern

      page_dir = File.join(settings.wiki_options[:page_file_dir].to_s,
                           settings.wiki_options[:base_path].to_s)
      # Home is a special case.
      path = '' if name.downcase == 'home'

      page_dir = File.join(page_dir, path)

      
      # write_page is not directory aware so use wiki_options to emulate dir support.
      wiki_options = settings.wiki_options.merge({ :base_path=>File.join(@base_url,params[:repo]), :page_file_dir => page_dir })
      wiki         = Gollum::Wiki.new(File.join(settings.repos_path,settings.wiki_repos_pattern,params[:repo] + '.git'), wiki_options)

      begin
        version = wiki.write_page(name, format, params[:content], commit_message)
        File.open(params[:repo] + "_" + version + ".json", "w") do |file|
          file.write params[:livewritingActions]
        end
        redirect to("/"+params[:repo]+"/#{clean_url(CGI.escape(::File.join(page_dir,name)))}")
      rescue Gollum::DuplicatePageError => e
        @repo = params[:repo]
        @message = "Duplicate page: #{e.message}"
        mustache :error
      end
    end

    post '/:repo/revert/:page/*' do
      protected!(params[:repo], params[:page], 'W')
      wikip        = wiki_page(params[:repo], params[:page])
      @path        = wikip.path
      @name        = wikip.name
      wiki         = wikip.wiki
      @page        = wiki.paged(@name,@path)
      shas         = params[:splat].first.split("/")
      sha1         = shas.shift
      sha2         = shas.shift

      if wiki.revert_page(@page, sha1, sha2, commit_message)
        redirect to("/"+params[:repo]+"/#{@page.escaped_url_path}")
      else
        sha2, sha1 = sha1, "#{sha1}^" if !sha2
        @versions  = [sha1, sha2]
        diffs      = wiki.repo.diff(@versions.first, @versions.last, @page.path)
        @diff      = diffs.first
        @message   = "The patch does not apply."
        @repo = params[:repo]
        mustache :compare
      end
    end

    post '/:repo/preview' do
      protected!(params[:repo], params[:page], 'R')
      opt      = settings.wiki_options.merge({ :base_path => File.join(@base_url,params[:repo]) })
      wiki     = wiki_new(File.join(settings.repos_path,settings.wiki_repos_pattern,params[:repo] + '.git'), opt)
      @name    = params[:page] || "Preview"
      @page    = wiki.preview_page(@name, params[:content], params[:format])
      @content = @page.formatted_data
      @toc_content = wiki.universal_toc ? @page.toc_data : nil
      @mathjax = wiki.mathjax
      @editable = false
      @repo = params[:repo]
      mustache :page
    end

    get '/:repo/history/*' do
      protected!(params[:repo], params[:page], 'R')
      @page        = wiki_page(params[:repo], params[:splat].first).page
      @page_num    = [params[:page].to_i, 1].max
      @versions    = @page.versions :page => @page_num
      @repo        = params[:repo]
      mustache :history
    end

    post '/:repo/compare/*' do
      protected!(params[:repo], params[:splat].first, 'R')
      @file     = params[:splat].first
      @versions = params[:versions] || []
      if @versions.size < 2
        redirect to("/"+params[:repo]+"/history/#{@file}")
      else
        redirect to("/"+params[:repo]+"/compare/%s/%s...%s" % [
          @file,
          @versions.last,
          @versions.first]
        )
      end
    end

    get %r{
      /([\w-]+)/compare/ # match any URL beginning with repo_name/compare/
      (.+)      # extract the full path (including any directories)
      /         # match the final slash
      ([^.]+)   # match the first SHA1
      \.{2,3}   # match .. or ...
      (.+)      # match the second SHA1
    }x do |repo_name, path, start_version, end_version|
      protected!(repo_name, path, 'R')
      wikip        = wiki_page(repo_name, path)
      @path        = wikip.path
      @name        = wikip.name
      @versions    = [start_version, end_version]
      wiki         = wikip.wiki
      @page        = wikip.page
      diffs        = wiki.repo.diff(@versions.first, @versions.last, @page.path)
      @diff        = diffs.first
      @repo        = repo_name
      mustache :compare
    end

    get %r{^/(javascript|css|images)} do
      halt 404
    end

    get %r{/([\w-]+)/(.+?)/([0-9a-f]{40})} do
      repo_name = params[:captures][0]
      file_path = params[:captures][1]
      version   = params[:captures][2]
      #protected!(repo_name, file_path, 'R')
      wikip     = wiki_page(repo_name, file_path, file_path, version)
      name      = wikip.name
      path      = wikip.path
      if page = wikip.page
        @page = page
        @name = name
        @content = page.formatted_data
        @editable = true
        @repo     = repo_name
        mustache :page
      else
        halt 404
      end
    end

    get '/:repo/search' do
      protected!(params[:repo], '/', 'R')
      @query = params[:q]
      wiki_options = settings.wiki_options.merge({ :base_path => params[:repo] })
      wiki = wiki_new(File.join(settings.repos_path,settings.wiki_repos_pattern,params[:repo] + '.git'), wiki_options)
      @results = wiki.search @query
      @name = @query
      @repo = params[:repo]
      mustache :search
    end

    get %r{
      /([\w-]+)/pages  # match any URL beginning with repo_name/pages
      (?:     # begin an optional non-capturing group
        /(.+) # capture any path after the "/pages" excluding the leading slash
      )?      # end the optional non-capturing group
    }x do |repo_name, path|
      protected!(repo_name, path, 'R')
      @path        = extract_path(path) if path
      wiki_options = settings.wiki_options.merge({ :page_file_dir => @path, :base_path => repo_name })
      wiki         = wiki_new(File.join(settings.repos_path,settings.wiki_repos_pattern, repo_name + '.git'), wiki_options)
      @results     = wiki.pages
      @results     += wiki.files if settings.wiki_options[:show_all]
      @ref         = wiki.ref
      @repo        = repo_name
      mustache :pages
    end

    # Fileview disabled
    #get '/:repo/fileview' do
    #  wiki_options = settings.wiki_options.merge({ :base_path => repo_name })
    #  wiki         = wiki_new(File.join(settings.repos_path,settings.wiki_repos_pattern, repo_name + '.git'), wiki_options)
    #  show_all     = settings.wiki_options[:show_all]
    #
    #  # if showing all files include wiki.files
    #  @results = show_all ? Gollum::FileView.new(wiki.pages + wiki.files, show_all).render_files :
    #                        Gollum::FileView.new(wiki.pages).render_files
    #  @ref         = wiki.ref
    #  @repo        = repo_name
    #  mustache :file_view, { :layout => false }
    #end

    get "/:repo/?" do
    #protected!(params[:repo], '/', 'R')
      redirect File.join(settings.wiki_options[:page_file_dir].to_s,settings.wiki_options[:base_path].to_s, params[:repo], 'Home')
    end

    get '/:repo/*' do
    protected!(params[:repo], params[:splat].join, 'R')
      show_page_or_file(params[:repo], params[:splat].first)
    end


    private

    # Options parameter to Gollum::Committer#initialize
    #     :message   - The String commit message.
    #     :name      - The String author full name.
    #     :email     - The String email address.
    # message is sourced from the incoming request parameters
    # author details are sourced from the session, to be populated by rack middleware ahead of us
    def commit_message
      commit_message = { :message => params[:message] }
      author_parameters = session['gollum.author']
      commit_message.merge! author_parameters unless author_parameters.nil?
      commit_message
    end
  end
end
