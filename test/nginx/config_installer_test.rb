require 'test_helper'

describe "Nginx ConfigInstaller" do
  before do
    @tmp = File.expand_path('../tmp').bypass_safe_level_1
    FileUtils.mkdir_p @tmp
    @vhost_file = File.join(@tmp, 'test.vhost.conf')
    
    @app = PassengerApplication.alloc.init
    @app.stubs(:application_type).returns(PassengerApplication::RAILS)
    @app.stubs(:config_path).returns(@vhost_file)
    @app.host = 'het-manfreds-blog.local'
    @app.path = '/User/het-manfred/rails code/blog'
    @app.environment = PassengerApplication::PRODUCTION
    @app.vhostname = 'het-manfreds-wiki.local:443'
    
    PassengerPaneConfig.stubs(:apache?).returns(false)
    @installer = ConfigInstaller.new([@app.to_hash].to_yaml)
  end
  
  after do
    #FileUtils.rm_rf @tmp
  end
  
  it "should initialize" do
    @installer.data.should == [{
      'app_type' => PassengerApplication::RAILS,
      'config_path' => @vhost_file,
      'host' => 'het-manfreds-blog.local',
      'path' => '/User/het-manfred/rails code/blog',
      'environment' => 'production',
      'vhostname' => 'het-manfreds-wiki.local:443',
      'user_defined_data' => "",
      'aliases' => ""
    }]
  end
  
  it "should be able to add a new entry to the hosts" do
    @installer.expects(:system).with("/usr/bin/dscl localhost -create /Local/Default/Hosts/het-manfreds-blog.local IPAddress 127.0.0.1")
    @installer.add_to_hosts(0)
  end
  
  it "should only add the main server_name host to the hosts if there are no aliases" do
    @installer.data[0]['aliases'] = ''
    @installer.expects(:system).with("/usr/bin/dscl localhost -create /Local/Default/Hosts/het-manfreds-blog.local IPAddress 127.0.0.1")
    @installer.add_to_hosts(0)
  end
  
  it "should write the correct vhost file for a Rails application" do
    @installer.create_vhost_conf(0)
    File.read(@vhost_file).should == %{
server \{
  server_name het-manfreds-blog.local;
  root "/User/het-manfred/rails code/blog/public";
  access_log /opt/local/var/log/nginx/het-manfreds-blog.local.access.log;
  error_log /opt/local/var/log/nginx/het-manfreds-blog.local.error.log;
  passenger_enabled on;
  rails_env production;
  #include /opt/local/etc/nginx/passenger_pane_servers/het-manfreds-blog.local.include;
\}}.sub(/^\n/, '')
  end
  
  it "should write the correct vhost file for a Rack application" do
    @app.stubs(:application_type).returns(PassengerApplication::RACK)
    @installer = ConfigInstaller.new([@app.to_hash].to_yaml)
    
    @installer.create_vhost_conf(0)
    File.read(@vhost_file).should == %{
server \{
  server_name het-manfreds-blog.local;
  root "/User/het-manfred/rails code/blog/public";
  access_log /opt/local/var/log/nginx/het-manfreds-blog.local.access.log;
  error_log /opt/local/var/log/nginx/het-manfreds-blog.local.error.log;
  passenger_enabled on;
  rack_env production;
  #include /opt/local/etc/nginx/passenger_pane_servers/het-manfreds-blog.local.include;
\}}.sub(/^\n/, '')
  end
  
  it "should check if the vhost directory exists, if not add it" do
    File.expects(:exist?).with(PassengerPaneConfig::PASSENGER_NGINX_APPS_DIR).returns(false)
    FileUtils.expects(:mkdir_p).with(PassengerPaneConfig::PASSENGER_NGINX_APPS_DIR)
    
    @installer.verify_nginx_vhost_conf
  end
  
  it "should check if our configuration to load the vhosts and passenger_ruby have been added to the nginx conf" do
    @nginx_conf = File.join(@tmp, 'test.nginx.conf')
    PassengerPaneConfig::NGINX_CONF = @nginx_conf
    conf = %{
http \{
\}}.sub(/^\n/, '')
    File.open(@nginx_conf, 'w') {|f| f.write(conf)}
    @installer.verify_nginx_conf
    File.read(@nginx_conf).should == %{
http \{
  passenger_ruby #{PassengerPaneConfig::PASSENGER_RUBY};
  passenger_root #{PassengerPaneConfig::PASSENGER_ROOT};
  include #{PassengerPaneConfig::PASSENGER_NGINX_APPS_DIR}/*.conf;
\}}.sub(/^\n/, '')
  end
  
  it "should not add the include configuration to the nginx conf if it exists" do
    @nginx_conf = File.join(@tmp, 'test.nginx.conf')
    PassengerPaneConfig::NGINX_CONF = @nginx_conf
    conf = %{
http \{
  include #{PassengerPaneConfig::PASSENGER_NGINX_APPS_DIR}/*.conf;
\}}.sub(/^\n/, '')
    File.open(@nginx_conf, 'w') {|f| f.write(conf)}
    @installer.verify_nginx_conf
    File.read(@nginx_conf).should == %{
http \{
  passenger_ruby #{PassengerPaneConfig::PASSENGER_RUBY};
  passenger_root #{PassengerPaneConfig::PASSENGER_ROOT};
  include #{PassengerPaneConfig::PASSENGER_NGINX_APPS_DIR}/*.conf;
\}}.sub(/^\n/, '')
  end

  it "should reload Nginx" do
    @installer.expects(:system).with(PassengerPaneConfig::NGINX_RELOAD_COMMAND)
    @installer.reload_nginx!
  end
  
  it "should be able to take a serialized array of hashes and do all the work necessary in one go" do
    installer = ConfigInstaller.any_instance
    
    installer.expects(:verify_nginx_vhost_conf)
    installer.expects(:verify_nginx_conf)
    
    installer.expects(:add_to_hosts).with(0)
    installer.expects(:add_to_hosts).with(1)
    
    installer.expects(:create_vhost_conf).with(0)
    installer.expects(:create_vhost_conf).with(1)
    
    installer.expects(:reload_nginx!)
    
    ConfigInstaller.new([{}, {}].to_yaml, 'extra command').install!
  end
end
