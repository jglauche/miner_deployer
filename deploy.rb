#!/usr/bin/env ruby

require "./lib/deployer"



d = Deployer.new("server" => ARGV[0],
								 "version" => ARGV[1],
								 "mode" => "install")
puts "deploying in 3 secs..."
sleep 3
d.deploy!
