#!/usr/bin/env ruby

require "./lib/deployer"


ARGV[0..-2].each do |server|
	d = Deployer.new("server" => server,
									 "version" => ARGV.last,
									 "mode" => "update_miner",
									 "skip_connect_check" => true)
	d.update_miner!
end
