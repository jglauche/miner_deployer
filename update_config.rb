#!/usr/bin/env ruby

require "./lib/deployer"


ARGV.each do |server|
	d = Deployer.new("server" => server,
									 "mode" => "update_config",
									 "skip_connect_check" => true)
	d.update_config!
end
