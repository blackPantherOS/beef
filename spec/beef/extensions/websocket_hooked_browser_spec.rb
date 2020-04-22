# encoding: UTF-8
require 'rest-client'
require 'core/main/network_stack/websocket/websocket'
require 'websocket-client-simple'

RSpec.describe 'BeEF WebSockets enabled' do

  before(:all) do
    @config = BeEF::Core::Configuration.instance
    @cert_key = @config.get('beef.http.https.key')
    @cert = @config.get('beef.http.https.cert')
    @port = @config.get('beef.http.websocket.port')
    @secure_port = @config.get('beef.http.websocket.secure_port')
    @config.set('beef.http.websocket.secure', true)
    @config.set('beef.http.websocket.enable', true)
   #set config parameters
   @config.set('beef.credentials.user', "beef")
   @config.set('beef.credentials.passwd', "beef")
   @username = @config.get('beef.credentials.user')
   @password = @config.get('beef.credentials.passwd')
   #load extensions, best practice is to reload as previous tests can potentially cause issues.
   print_info "Loading in BeEF::Extensions"
   BeEF::Extensions.load
   sleep 2
   if @config.get('beef.module').nil?
     puts "loading modules"
     BeEF::Modules.load
     sleep 2
   end
   #generate token for the api to use
   BeEF::Core::Crypto::api_token
   # load up DB
   # Connect to DB
   ActiveRecord::Base.logger = nil
   OTR::ActiveRecord.migrations_paths = [File.join('core', 'main', 'ar-migrations')]
   OTR::ActiveRecord.configure_from_hash!(adapter:'sqlite3', database:'beef.db')
   
   # Migrate (if required)
   context = ActiveRecord::Migration.new.migration_context
   if context.needs_migration?
     puts "migrating db"
     ActiveRecord::Migrator.new(:up, context.migrations, context.schema_migration).migrate
   end
   #start the hook server instance, for it out to track the pids for graceful closure
   http_hook_server = BeEF::Core::Server.instance
   http_hook_server.prepare
   @pids = fork do
     BeEF::API::Registrar.instance.fire(BeEF::API::Server, 'pre_http_start', http_hook_server)
   end
   @pid = fork do
     http_hook_server.start
   end
   # wait for server to start
   sleep 1
  end

  it 'can hook a browser with websockets', :run_on_browserstack => true do
    #prepare for the HTTP model
    https = BeEF::Core::Models::Http

    ### hook a new victim, use rest API to send request and get the token and victim

    api = BeefRestClient.new('http', ATTACK_DOMAIN, '3000', BEEF_USER, BEEF_PASSWD)
    response = api.auth()
    @token = response[:token]

		# Hook new victim
		print_info 'Hooking a new victim, waiting a few seconds...'
		victim = @driver.navigate.to "#{VICTIM_URL}"

		# Give time for browser hook to occur
		sleep 3

    #Uses the response and hooked browser details to get the response
    response = RestClient.get "#{RESTAPI_HOOKS}", {:params => {:token => @token}}
    #test for the response if errors and weirdness there
    # puts "#{response} from the rest client " 
    hb_details = JSON.parse(response.body)

    #get the hooked browser details
    hb_session = hb_details["hooked-browsers"]["online"]["0"]["session"]
    #show the address of what is being hooked
    #puts "hooked browser: #{hb_session}"
    expect(hb_session).not_to be_nil  
    #cannot do it in the after:all
    https.where(:hooked_browser_id => hb_session).delete_all
  end

  after(:all) do
    # cleanup: delete test browser entries and session
    # kill the server
    @config.set('beef.http.websocket.enable', false)
    Process.kill("KILL", @pid)
    Process.kill("KILL", @pids)
    puts "waiting for server to die.."
  end

end