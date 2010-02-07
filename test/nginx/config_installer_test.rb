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
    FileUtils.rm_rf @tmp
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
  
  it "should only add the main ServerName host to the hosts if there are no aliases" do
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
    File.expects(:exist?).with(PassengerPaneConfig::PASSENGER_APPS_DIR).returns(false)
    FileUtils.expects(:mkdir_p).with(PassengerPaneConfig::PASSENGER_APPS_DIR)
    
    @installer.verify_vhost_conf
  end
  
  it "should check if our configuration to load the vhosts has been added to the apache conf yet" do
    File.stubs(:read).with(PassengerPaneConfig::HTTPD_CONF).returns("Include #{PassengerPaneConfig::APACHE_DIR}/other/*.conf")
    
    file_mock = mock("Apache conf")
    File.expects(:open).with(PassengerPaneConfig::HTTPD_CONF, 'a').yields(file_mock)
    file_mock.expects(:<<).with(%{

# Added by the Passenger preference pane
# Make sure to include the Passenger configuration (the LoadModule,
# PassengerRoot, and PassengerRuby directives) before this section.
<IfModule passenger_module>
  NameVirtualHost *:80
  <VirtualHost *:80>
    ServerName _default_
  </VirtualHost>
  Include #{PassengerPaneConfig::PASSENGER_APPS_DIR}/*.conf
</IfModule>})

    @installer.verify_httpd_conf
  end
  
  it "should not add the vhosts configuration to the apache conf if it's in there already" do
    File.stubs(:read).with(PassengerPaneConfig::HTTPD_CONF).returns(%{
Include #{PassengerPaneConfig::APACHE_DIR}/other/*.conf

# Added by the Passenger preference pane
# Make sure to include the Passenger configuration (the LoadModule,
# PassengerRoot, and PassengerRuby directives) before this section.
<IfModule passenger_module>
  NameVirtualHost *:80
  <VirtualHost *:80>
    ServerName _default_
  </VirtualHost>
  Include #{PassengerPaneConfig::PASSENGER_APPS_DIR}/*.conf
</IfModule>})
    
    File.expects(:open).times(0)
    @installer.verify_httpd_conf
  end
  
  it "should not check if our configuration to load the vhosts has been added to the apache conf yet" do
    File.stubs(:read).with(PassengerPaneConfig::HTTPD_CONF).returns("Include #{PassengerPaneConfig::APACHE_DIR}/other/*.conf")
    
    file_mock = mock("Apache conf")
    File.expects(:open).with(PassengerPaneConfig::HTTPD_CONF, 'a').yields(file_mock)
    file_mock.expects(:<<).with(%{

# Added by the Passenger preference pane
# Make sure to include the Passenger configuration (the LoadModule,
# PassengerRoot, and PassengerRuby directives) before this section.
<IfModule passenger_module>
  NameVirtualHost *:80
  <VirtualHost *:80>
    ServerName _default_
  </VirtualHost>
  Include #{PassengerPaneConfig::PASSENGER_APPS_DIR}/*.conf
</IfModule>})
    
    @installer.verify_httpd_conf
  end
  
  it "should restart Apache" do
    @installer.expects(:system).with(PassengerPaneConfig::APACHE_RESTART_COMMAND)
    @installer.restart_apache!
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
