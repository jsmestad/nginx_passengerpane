#!/usr/bin/env ruby

require 'osx/cocoa'
require 'yaml'
require 'fileutils'
require File.expand_path('../passenger_pane_config', __FILE__) unless ENV['TESTING_PASSENGER_PREF']

class String
  def bypass_safe_level_1
    str = dup
    str.untaint
    str
  end
end

class ConfigInstaller
  attr_reader :data
  
  def initialize(yaml_data, extra_command = nil)
    @data = YAML.load(yaml_data)
    @extra_command = extra_command
  end
  
  def add_to_hosts(index)
    server_name = @data[index]['host']
    [server_name, *@data[index]['aliases'].split(' ')].each do |host|
      OSX::NSLog("Will add host: #{host}")
      system "/usr/bin/dscl localhost -create /Local/Default/Hosts/#{host.bypass_safe_level_1} IPAddress 127.0.0.1"
    end
  end
  
  def verify_vhost_conf
    unless File.exist? PassengerPaneConfig::PASSENGER_APPS_DIR
      OSX::NSLog("Will create directory: #{PassengerPaneConfig::PASSENGER_APPS_DIR}")
      FileUtils.mkdir_p PassengerPaneConfig::PASSENGER_APPS_DIR
    end
  end

  def verify_nginx_vhost_conf
    unless File.exist? PassengerPaneConfig::PASSENGER_NGINX_APPS_DIR
      OSX::NSLog("Will create directory: #{PassengerPaneConfig::PASSENGER_NGINX_APPS_DIR}")
      FileUtils.mkdir_p PassengerPaneConfig::PASSENGER_NGINX_APPS_DIR
    end
  end

  def gsub_file(path, regexp, *args, &block)
    content = File.read(path).gsub(regexp, *args, &block)
    File.open(path, 'wb') { |file| file.write(content) }
  end
  
  def verify_nginx_conf
    conf = PassengerPaneConfig::NGINX_CONF
    content = File.read(conf)
    a = []
    a << "http {"
    if !content.match(/^\s*passenger_ruby\s+/)
      a << "  passenger_ruby #{PassengerPaneConfig::PASSENGER_RUBY};"
    end
    if !content.match(/^\s*passenger_root\s+/)
      a << "  passenger_root #{PassengerPaneConfig::PASSENGER_ROOT};"
    end
    if !content.include? "include #{PassengerPaneConfig::PASSENGER_NGINX_APPS_DIR}/*.conf"
      a << "  include #{PassengerPaneConfig::PASSENGER_NGINX_APPS_DIR}/*.conf;"
    end
    gsub_file PassengerPaneConfig::NGINX_CONF, /http\s+\{/ do |match|
        a.join("\n")
    end
  end

  def verify_httpd_conf
    unless File.read(PassengerPaneConfig::HTTPD_CONF).include? "Include #{PassengerPaneConfig::PASSENGER_APPS_DIR}/*.conf"
      OSX::NSLog("Will try to append passenger pane vhosts conf to: #{PassengerPaneConfig::HTTPD_CONF}")
      File.open(PassengerPaneConfig::HTTPD_CONF, 'a') do |f|
        f << %{

# Added by the Passenger preference pane
# Make sure to include the Passenger configuration (the LoadModule,
# PassengerRoot, and PassengerRuby directives) before this section.
<IfModule passenger_module>
  NameVirtualHost *:80
  <VirtualHost *:80>
    ServerName _default_
  </VirtualHost>
  Include #{PassengerPaneConfig::PASSENGER_APPS_DIR}/*.conf
</IfModule>}
      end
    end
  end
  
  def create_vhost_conf(index)
    if !PassengerPaneConfig.apache?
      create_nginx_vhost_conf index
      return
    end
    
    app = @data[index]
    public_dir = File.join(app['path'], 'public')
    vhost = [
      "<VirtualHost #{app['vhostname']}>",
      "  ServerName #{app['host']}",
      ("  ServerAlias #{app['aliases']}" unless app['aliases'].empty?),
      "  DocumentRoot \"#{public_dir}\"",
      "  #{app['app_type'].capitalize}Env #{app['environment']}",
      (app['user_defined_data'] unless app['user_defined_data'].empty?),
      "</VirtualHost>"
    ].compact.join("\n")
    
    OSX::NSLog("Will write vhost file: #{app['config_path']}\nData: #{vhost}")
    File.open(app['config_path'].bypass_safe_level_1, 'w') { |f| f << vhost }
  end
  
  def create_nginx_vhost_conf(index)
    app = @data[index]
    public_dir = File.join(app['path'], 'public')
    include_file = "#{PassengerPaneConfig::PASSENGER_NGINX_APPS_DIR}/#{@data[index]['host'].bypass_safe_level_1}.include"
    vhost = [
      "server {",
      "  server_name #{app['host']};",
      "  root \"#{public_dir}\";",
      "  access_log /opt/local/var/log/nginx/#{app['host']}.access.log;",
      "  error_log /opt/local/var/log/nginx/#{app['host']}.error.log;",
      "  passenger_enabled on;",
      "  #{app['app_type'].downcase}_env #{app['environment']};",
      "  #include #{include_file};",
      "}"
    ].compact.join("\n")

    OSX::NSLog("Will write nginx vhost file: #{app['config_path']}\nData: #{vhost}")
    File.open(app['config_path'].bypass_safe_level_1, 'w') { |f| f << vhost }
  end

  def restart_apache!
    system PassengerPaneConfig::APACHE_RESTART_COMMAND
  end
  
  def reload_nginx!
    system PassengerPaneConfig::NGINX_RELOAD_COMMAND
  end

  def install!
    if PassengerPaneConfig.apache?
      verify_vhost_conf
      verify_httpd_conf
    else
      verify_nginx_vhost_conf
      verify_nginx_conf
    end
    
    (0..(@data.length - 1)).each do |index|
      add_to_hosts index
      create_vhost_conf index
    end
    if PassengerPaneConfig.apache?
      restart_apache!
    else
      reload_nginx!
    end
  end
end

if $0 == __FILE__
  OSX::NSLog("Will try to write config(s).")
  ConfigInstaller.new(*ARGV).install!
end