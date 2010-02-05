#!/usr/bin/env ruby

require 'osx/cocoa'
require 'yaml'
require File.expand_path('../passenger_pane_config', __FILE__) unless ENV['TESTING_PASSENGER_PREF']

class String
  def bypass_safe_level_1
    str = dup
    str.untaint
    str
  end
end

class ConfigUninstaller
  attr_reader :data
  
  def initialize(yaml_data)
    @data = YAML.load(yaml_data)
  end
  
  def remove_from_hosts(index)
    server_name = @data[index]['host']
    [server_name, *@data[index]['aliases'].split(' ')].each do |host|
      OSX::NSLog("Will remove host: #{host}")
      system "/usr/bin/dscl localhost -delete /Local/Default/Hosts/#{host.bypass_safe_level_1}"
    end
  end
  
  def remove_vhost_conf(index)
    OSX::NSLog("Will remove vhost file: #{config_path(index)}")
    File.delete config_path(index)
  end
  
  def config_path(index)
    "#{PassengerPaneConfig::PASSENGER_APPS_DIR}/#{@data[index]['host'].bypass_safe_level_1}.#{PassengerPaneConfig::PASSENGER_APPS_EXTENSION}"
  end

  def remove_nginx_vhost_conf(index)
    File.delete nginx_config_path(index)
  end

  def nginx_config_path(index)
    "#{PassengerPaneConfig::PASSENGER_NGINX_APPS_DIR}/#{@data[index]['host'].bypass_safe_level_1}.#{PassengerPaneConfig::PASSENGER_NGINX_APPS_EXTENSION}"
  end
  
  def restart_apache!
    system PassengerPaneConfig::APACHE_RESTART_COMMAND
  end
  
  def reload_nginx!
    system PassengerPaneConfig::NGINX_RELOAD_COMMAND
  end

  def uninstall!
    (0..(@data.length - 1)).each do |index|
      remove_from_hosts index
      if PassengerPaneConfig.apache?
        remove_vhost_conf index
      else
        remove_nginx_vhost_conf index
      end
    end
    if PassengerPaneConfig.apache?
      restart_apache!
    else
      reload_nginx!
    end
  end
end

if $0 == __FILE__
  OSX::NSLog("Will try to remove config(s).")
  ConfigUninstaller.new(ARGV.first).uninstall!
end