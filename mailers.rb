class Mailer
  
  def initialize( config = {} )
    @from = config[:from]
    @to = config[:to]
  end

  def get_key( keysource )
    if nil == keysource
      nil
    else 
      keyfile = File.new( keysource, 'r')    
      apikey = keyfile.readline.rstrip
      keyfile.close
      apikey
    end
  end

  def email( params )
    params_mod = params.dup   # carries over keys not explicitly processed
    params_mod[:from] = params[:from] ? params[:from] : @from
    params_mod[:to] = params[:to] ? params[:to] : @to
    if !params_mod[:from] || !params_mod[:to]
      puts "email not sent because from/to not specified: from: #{params_mod[:from]}, to: #{params_mod[:to]}, subject: #{params[:subject]}"
      return false
    end
    params_mod[:to] = params_mod[:to].class == String ? [params_mod[:to]] : params_mod[:to]  #canonical is array
    params_mod[:body] = params[:body] ? params[:body] : "(email body text not specified)\n\n"
    if !params_mod[:subject]
      puts "email from #{params_mod[:from]} to #{params_mod[:to]} not sent because no subject specified"
      return false
    else
      return send_email( params_mod )      
    end
  end

# parent class merely similates send with output to terminal 
  def send_email( params )
    puts "From: #{params[:from]}"
    puts "To: #{params[:to]}"
    puts "Email subject: #{params[:subject]}"
    puts "Email body: #{params[:body]}"  
    return true
  end

end


class ViaSendGrid < Mailer
  require 'sendgrid-ruby'
  include SendGrid
  require 'json'

  def initialize( config = {} )
    @apikey = ENV['SENDGRID_API_KEY'] ? ENV['SENDGRID_API_KEY'] : get_key( config[:key_location] )  
    if !@apikey
      puts "** SendGrid API key not set; alerts can't be sent **"
      abort
    end
    @sandbox = config[:sandbox_mode]
    super( config )
  end

# invoke send_email via parent-class method email  
  def send_email( params, silent = false )
    mail = Mail.new
    mail.from = Email.new(email: params[:from])
    mail.subject = params[:subject][0...78] if params[:subject] # SendGrid limits subject to 78 characters
    personalization = Personalization.new
    params[:to].each do |address|
      personalization.to = Email.new(:email => address)
    end
    mail.personalizations = personalization
    mail.contents = Content.new(type: 'text/plain', value: params[:body])
    if @sandbox
      mail_settings = MailSettings.new
      mail_settings.sandbox_mode = SandBoxMode.new(enable: true)
      mail.mail_settings = mail_settings
    end
    sg = SendGrid::API.new(api_key: @apikey, host: 'https://api.sendgrid.com')
    response = sg.client.mail._('send').post(request_body: mail.to_json)
    status = response.status_code.to_i
    if ( !status || status > 299 )
      if !silent 
        puts "email via SendGrid failed with status code #{status}"
        puts "for status code descriptions see https://sendgrid.com/docs/API_Reference/Web_API_v3/Mail/errors.html\n"
        puts response.body
      end
      return false
    else
      return true
    end
  end

end  

=begin

# NOT TESTED: legacy code kept to indicate how to use a different mail service
class ViaPony < Mailer
  require 'pony'
  def send_email( params )
    message_params =  { 
                      from: @from,
                      to:   params[:to],
                      subject: params[:subject],
                      text:    params[:body]
                      }
    Pony.mail( message_params )
  end
end


# NOT TESTED: legacy code kept to indicate how to use a different mail service
class ViaMailgun < Mailer
  require 'mailgun'

  def initialize( config )
    @sending_domain = config[:sending_domain]
    super( config )
  end

  def send_email( params )
    @api = ENV['MAILGUN_API_KEY'] if nil == @api_key
    if !@apikey
      puts "** MailGun API key not set; alerts can't be sent **"
      abort
    end    
#   mg_client = Mailgun::Client.new( @apikey, "bin.mailgun.net", "36751b9b", ssl = false )
    mg_client = Mailgun::Client.new( @apikey )
    mb_obj = Mailgun::MessageBuilder.new
    mb_obj.from(@from)
    params[:to].each do |address|
      mb_obj.add_recipient(:to, address)
    end
    mb_obj.subject(params[:subject])
    mb_obj.body_text(params[:body])
    ret = mg_client.send_message(@sending_domain, mb_obj)
# send message produces /usr/local/rvm/gems/ruby-2.3.0/gems/mailgun-ruby-1.1.0/lib/mailgun/client.rb:58:in `rescue in post': 400 Bad Request (Mailgun::CommunicationError)    
# if an email address isn't verified!!
#   puts "mg ret: #{ret.inspect}"
  end

end

=end