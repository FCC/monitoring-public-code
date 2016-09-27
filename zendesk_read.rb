require 'json'
require 'curb'

# data source class
class ZendeskRead 
  
  def initialize( config )
    # API call parameters
    @BaseURL = config[:zendesk_url] + '/api/v2/views/'
    @Agent = config[:agent_email] + '/token' 
    
    # API key (for agent with maximally limited, read-only role) stored separately from code to avoid inadvertent disclosure
    if config[:key_location]
      keyfile = File.new( config[:key_location], 'r')
      @ZDAPI = keyfile.readline.rstrip
      keyfile.close
    else
      @ZDAPI = ENV['ZD_KEY']
    end
    if !@ZDAPI
      puts "** Zendesk view reader API key not set **"
      abort
    end
  end    
  
  # call Zendesk API
  def view_counts( view_ids )           
    view_ids = [view_ids] if view_ids.class == Fixnum || view_ids.class == String
    view_ids = view_ids.to_a if view_ids.class == Set
    if Array == view_ids.class
      gURL = @BaseURL + "/count_many.json?ids=#{view_ids.join(',')}"
      c = Curl::Easy.new( gURL ) 
      c.http_auth_types = :basic
      c.username = @Agent
      c.password = @ZDAPI
      c.perform
      begin
        returnObj = JSON.parse( c.body_str, :symbolize_names => true )
      rescue
        returnObj = { error: c.body_str } 
      end
      returnObj 
    else
      {error: "view ids parameter not properly formed: #{view_ids}"}
    end
  end  

end
