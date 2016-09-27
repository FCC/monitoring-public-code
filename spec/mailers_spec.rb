require_relative '../mailers.rb'

RSpec.describe Mailer do

  let(:params) { {from: "person@example.com",
                  to: ["recipient1@example.com", "recipient2@example.com"],
                  subject: "email subject",
                  body: "body of email",
                  other_key: "value"
                } }
                
  describe "#email" do

    context ":to (array), :from, :subject, and :body keys specified" do

      it "with :to as array, calls #send_email with given paramaters, returns :subject" do
        mailer = Mailer.new
        expect(mailer).to receive(:send_email).with(params).and_return(params[:subject]) #note: return is for mailer object, not send_mail method
        mailer.email(params)
      end
      
      it "with :to as string, converts :to to array & calls #send_email with given paramaters" do
        params[:to] = "recipient1@example.com"
        params_mod = params.dup
        params_mod[:to] = ["recipient1@example.com"]
        mailer = Mailer.new
        expect(mailer).to receive(:send_email).with(params_mod).and_return(params[:subject]) 
        mailer.email(params)
      end
        
    end

    context ":from address not specified" do

      it "if config :from address specified, sends email using it" do
        params[:from] = nil
        config = {from: "from_default@example.com" }
        mailer = Mailer.new( config )
        expect(mailer).to receive(:send_email).with(hash_including(:from => "from_default@example.com"))
        mailer.email(params)
      end

      it "if config :from address not specified, doesn't send email" do
        params[:from] = nil
        mailer = Mailer.new
        expect(mailer).not_to receive(:send_email)
        expect(mailer).to receive(:email).and_return(nil)
        mailer.email(params)
      end
    end
    
    context ":to address not specified" do

      it "if config :to address specified, sends email using it" do
        params[:to] = nil
        config = {to: "to_default@example.com" }
        mailer = Mailer.new( config )
        expect(mailer).to receive(:send_email).with(hash_including(:to => ["to_default@example.com"]))
        mailer.email(params)
      end

      it "if config :to address not specified, doesn't send email" do
        params[:to] = nil
        mailer = Mailer.new
        expect(mailer).not_to receive(:send_email)
        expect(mailer).to receive(:email).and_return(nil)
        mailer.email(params)
      end
    end

    context ":subject not specified" do

      it "doesn't send email" do
        params[:subject] = nil
        mailer = Mailer.new
        expect(mailer).not_to receive(:send_email)
        expect(mailer).to receive(:email).and_return(nil)
        mailer.email(params)
      end
    end

    context ":body not specified" do

      it "sends email with inserted default text '(email body text not specified)'" do
        params[:body] = nil
        mailer = Mailer.new
        expect(mailer).to receive(:send_email).with(hash_including(:body => "(email body text not specified)\n\n"))
        mailer.email(params)
      end
    end

  end

end


RSpec.describe ViaSendGrid do
  
  let(:mailer) { ViaSendGrid.new(sandbox_mode: true) }

  let(:silent) {true}
  
  let(:params) { {from: "person@example.com",
                  to: ["recipient1@example.com", "recipient2@example.com"],
                  subject: "email subject",
                  body: "body text"
                } }
  
  describe "#send_email" do

    context ":from, :to, :subject, :body specified in params hash" do
      it "sends email" do
        expect(mailer.send_email(params)).to eql(true)
      end
    end
    
    context ":body omitted in params hash" do
      it "fails to send email" do
        params[:body] = nil
        expect(mailer.send_email(params, silent)).to eql(false)
      end
    end    

    context ":subject omitted in params hash" do
      it "fails to send email" do
        params[:subject] = nil
        expect(mailer.send_email(params, silent)).to eql(false)
      end
    end       
    
  end
  
end