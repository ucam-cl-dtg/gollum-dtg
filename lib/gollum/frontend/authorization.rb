require 'net/http'
require 'uri'
require 'json'

module Sinatra
  module Authorization
 
  def auth
    @auth ||= Rack::Auth::Basic::Request.new(request.env)
  end
 
  def unauthorized!(realm=request.host)
    response['WWW-Authenticate'] = %(Basic realm="#{realm}")
    throw :halt, [ 401, 'Authorization Required' ]
  end
 
  def bad_request!
    throw :halt, [ 400, 'Bad Request' ]
  end
 
  def authorized?
    request.env['REMOTE_USER']
  end
 
  def authorize(username, password)
    # Start off by clearing out last name info
    request.env['REMOTE_USER'].delete if !request.env['REMOTE_USER'].nil?

    # Assume this is a github repo, auth won't be enforced in app.rb if not github
    repo = `cd #{settings.gollum_path}; git config --get remote.origin.url`.strip.split(":")
    return true if repo.empty? # Shouldn't have been called, just here to prevent 500s
    repo_loc = repo.last.split("/")
    uri = URI.parse("http://github.com/api/v2/json/repos/show/#{repo_loc[0]}/#{repo_loc[1].split(".").first}/collaborators")
    http = Net::HTTP.new(uri.host, uri.port)
    req = Net::HTTP::Get.new(uri.request_uri)
    req.basic_auth(username, password)
    response = http.request(req)

    # This will be 404 or 500 or 400 if the wrong details are supplied or user isn't a collaborator
    # There will always be at least one collaborator, the owner
    if response.header.code == "200"
	obj = JSON.parse(response.body)

        if !obj['collaborators'].nil? && obj['collaborators'].include?(username)

	  # User is a valid user and a collaborator, let's get their details
	  uri = URI.parse("http://github.com/api/v2/json/user/show/#{username}")
	  http = Net::HTTP.new(uri.host, uri.port)
	  req = Net::HTTP::Get.new(uri.request_uri)
	  req.basic_auth(username, password)
	  response = http.request(req)
	  if response.header.code == "200"
	    obj = JSON.parse(response.body)
	    request.env['REMOTE_USER'] = {'name' => obj['user']['name'], 'email' => obj['user']['email']}
	    return true
	  else
	    # There was an error getting their details
            return false
	  end
	end
    else
	return false
    end
  end
 
  def require_authorization
    repo = `cd #{settings.gollum_path}; git config --get remote.origin.url`.strip.split(":")
    return if repo.nil? || repo[0] != "git@github.com"
    return if authorized?
    unauthorized! unless auth.provided?
    bad_request! unless auth.basic?
    unauthorized! unless authorize(*auth.credentials)
  end
 
  def admin?
    authorized?
  end
 
  end
end