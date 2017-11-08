require 'rubygems'
require 'bundler'
require 'digest'
require 'pp'
require 'yaml'

Bundler.require

set :logging, true
config = YAML.load_file("config.yml")

URL = "https://graph.facebook.com/v2.6/me/messages?access_token=#{config['config']['facebook_access_token']}"
CHATURL = config['config']['chatbot_url']
CHAT_SECRET = config['config']['chatbot_secret']
TRANS_KEY = config['config']['translation_key']

TranslationApiClient::Swagger.configure do |configuration|
	configuration.key = TRANS_KEY
end

get '/' do  
	puts "Got root"
  result = TranslationApiClient::TranslationApi.translation_translate_get("The quick brown fox jumps over the lazy dog", "fr")
  result.outputs[0].output
end 

get '/webhook' do
	puts "Challenge received #{params['hub_verify_token']}"
	params['hub.challenge'] if 'fbToken' == params['hub.verify_token']
end

sessions = {

}

post '/webhook' do
	puts "Received webhook"
  body = request.body.read
  payload = JSON.parse(body)

  # get the sender of the message
 	sender = payload["entry"].first["messaging"].first["sender"]["id"]
  
  # get the message text
  message = payload["entry"].first["messaging"].first["message"]
  message = message["text"] unless message.nil?
  
  pp message

  # translate it to english
  result = TranslationApiClient::TranslationApi.translation_translate_get(message, "en")
  unless result.nil?
  	trans_msg = result.outputs[0].output
	  trans_lang = result.outputs[0].detected_language

	  puts "Message from #{sender} (in #{trans_lang})" 

	  sessions[sender] = trans_lang
		unless message.nil?
	    
	    ibcs_payload = { :userId => sender,
	    						:userProfile => { :firstName => 'Joel', :lastName => 'Nation'},
	    						:text => trans_msg
	    					}.to_json

	    signature = OpenSSL::HMAC.hexdigest('SHA256', CHAT_SECRET, ibcs_payload)
	    puts "Signature: #{signature}"
	    puts "Payload: #{ibcs_payload}"
	    
	    @result = HTTParty.post(CHATURL, 
	    		:body => ibcs_payload,
	    		:verify => false,
	    		:headers => { 'X-Hub-Signature' => "sha256=#{signature}"})
	    pp @result
	  end
	end
end

# The reply from IBCS
post '/chathook' do
	puts "Received chatbot reply"
 	body = request.body.read
  payload = JSON.parse(body)
  pp payload

  sender = payload["userId"]
  msg = payload["text"]

  puts "User has language set: #{sessions[sender]}"
	# translate it to their language
  result = TranslationApiClient::TranslationApi.translation_translate_get(msg, sessions[sender])
  unless result.nil?
    trans_msg = result.outputs[0].output
	  puts "Sending #{trans_msg} to #{sender}"

		@result = HTTParty.post(URL, 
	        :body => { :recipient => { :id => sender}, 
	                   :message => { :text => trans_msg}
	                 }.to_json,
	        :headers => { 'Content-Type' => 'application/json' } )
	end
end
