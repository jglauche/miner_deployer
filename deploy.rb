#!/usr/bin/env ruby

require "./lib/deployer"



d = Deployer.new(ARGV)
puts "deploying in 3 secs..."
sleep 3
d.deploy!
