require 'optparse'

class Deployer

	def initialize(options={})
		if options.size == 0
			options = ["--help"]
		end
		@mode = "install"
		@version = "gcc7.2.0"
		
		@connect_to = default_connect_to
		@av = 1
		@algo = "cryptonight"
		
		opt_parser = OptionParser.new do |opts|
			opts.on("-s","--server SERVER", "Server to deploy to") do |s|
				@server = s
			end
			opts.on("-m", "--mode=", "Mode: install (default), update_config, update_miner") do |m|
				@mode = m
			end
			opts.on("-b", "--binary=", "install this binary version (default gcc7.2.0)") do |b|
				@version = b
			end
			opts.on("-S","--skip-connection-checks","skips checking the SSH connection before doing things") do |s|
				@skip_connect_check = true
			end
			opts.on("-c","--miner-connection=", "Connect miner to pool or proxy; for example stratum+tcp://127.0.0.1:3333") do |c|
				@connect_to = c			
			end	
			opts.on("--av=","--av setting to xmrig (default 1)") do |av|
				@av = av
			end
			opts.on("-u","--username=", "Username for pool") do |u|
				@login = u
			end
			opts.on("-p", "--password=","Password for pool") do |p|
				@passsword = p
			end
			opts.on("-a", "--algo=","algorithm, [cryptonight, cryptonight-lite] default: cryptonight") do |a|
				@algo = a
			end
			opts.on("-t", "--threads=", "threads (leave blank for auto detect)") do |t|
				@override_threads = t
			end
			# TODO: 
			# - manual affinity
			opts.on("-h","--help", "This help") do |h|
				help
				puts opts
				exit
			end
		end
		opt_parser.parse!(options)
		if !@server 	
			puts "no server defined"
			exit
		end

		sanity_checks
		check_cpu
		info
	end

	def default_connect_to
		"stratum+tcp://136.243.60.144:3333" 
	end

	def sanity_checks
		if @server.to_s == ""
			return help
		end
		if @server == default_connect_to
			puts "Warning: using default server, please use the -c command to use your pool"
		end

		if @mode == "install" and !File.exists?(binary_path)
			puts "Error, expected file does not exist: #{binary_path}"
			exit
		end
		try_ssh unless @skip_connect_check
		puts "Sanity checks done" 
	end

	def help
		puts "The Miner Deployer assumes that you have a Debian 9 system, upgrades parts to debian sid." 
		puts "assumes that you have put your public ssh key in /root/.ssh/authorized_keys"
	end

	def info
		case @mode
			when "install"
				puts "Deploying on #{@server} with xmrig #{@version}"
			when "update_config"
				puts "Updating miner config on #{@server}" 
		end
	end

	def try_ssh
		puts "checking if server access works... "
		res = remote_query("echo 'works'")
		exit unless res.include? "works"
		puts "OK."
	end

	def check_cpu
		puts "Checking CPU..."
		res = remote_query("lscpu |egrep '^Core|^Model name|^CPU\\(s\\)|^Socket|^L3'") 	
		@cpus = nil
		@cores = nil
		@processor = nil
		@sockets = nil
		res.split("\n").each do |a|
			b = a.split(":")		
			if b[0].to_s.include? "Model name"
				@processor = b[1].strip.split(" ")[0..-3].join(" ")
				@processor_speed = b[1].strip.split(" ").last
			elsif b[0].to_s.include? "Core"
				@cores = b[1].to_i
			elsif b[0].to_s.include? "CPU"
				@cpus = b[1].to_i
			elsif b[0].to_s.include? "Socket"
				@sockets = b[1].to_i
			elsif b[0].to_s.include? "L3"
				@l3_cache = b[1].gsub("K","").to_i
			else
				puts "[debug]: #{b[0]}"
			end
		end

		if @processor == nil or @cores == nil or @cpus == nil or @sockets == nil
			puts "could not determine processor or core count"
			exit
		end

		puts "found processor: #{@processor}, Speed: #{@processor_speed}"
		puts "found cpus: #{@cpus}"
		puts "found sockets: #{@sockets}"
		puts "found cores per socket: #{@cores}"
		puts "L3 cache: #{@l3_cache}"
		puts "Configuring for algorithm #{@algo} and thread count: #{thread_count}"	
		determine_affinity

		check_processor_blacklist
	end


	def determine_affinity	
		if @cpus == 1 or @cpus == @cores*@sockets
			puts "no affinity setting needed"
			@affinity = nil
		else
			@affinity = "0x"+(2**@cores-1).to_s(16).upcase
			puts "Using affinity #{@affinity}"
		end
	end

	def check_processor_blacklist
		# FIXME: when testing deployment on cloud servers I'd sometimes get on really shitty ones for cryptonight mining
		# This should be user definable. 
		@blacklist = ["Intel(R) Xeon(R) CPU E5520"]
		if @blacklist.include? @processor
			puts "Processor blacklisted, aborting."	
			exit
		end
	end

	def remote_query(cmd,user="root")
		res = `ssh #{user}@#{@server} #{cmd}`
		return res
	end
	
	def remote(cmd,user="root")
		command = "ssh #{user}@#{@server} '#{cmd}'" 		
		execute(command)
	end

	def copy(file, destination, user="root", flag="")
		command = "scp #{flag} #{file} #{user}@#{@server}:#{destination}"
		execute(command)
	end

	def execute(cmd)
		puts cmd
		system cmd
	end

	def binary_path
		"./xmrig_versions/#{@version}/xmrig"
	end

	def thread_count
		if @override_threads
			return @override_threads
		end
		# check for low cache
		if @l3_cache
			case @algo
			when 'cryptonight'
				@max_threads = @l3_cache / 2048
			when 'cryptonight-lite'
				@max_threads = @l3_cache / 1024
			else
				puts "could not determine maximum number of threads"
			end
			if @max_threads && @max_threads < @cores*@sockets
				return @max_threads
			end
		end
	
		# usually, use all physical cores
		return @cores*@sockets
	end

	def miner_config
		aff_str = ""
		algo_str = ""
		login_str =""
		if @affinity
			aff_str = "--cpu-affinity #{@affinity}"
		end
		if @algo != "cryptonight"
			algo_str = "-a #{@algo}"
		end
		if @login
			login_str ="-u #{@login} "
		end
		if @password
			login_str += "-p #{@password}"
		end

		f = File.open("miner.sh","w")
		f.write "cd ~/xmrig && nice -n 19 ./xmrig -o #{@connect_to} #{login_str} -t #{thread_count} --av #{@av} --nicehash #{aff_str} #{algo_str}\n".split(" ").join(" ")
		f.close
	end

	def install_miner_config
		miner_config
		copy("miner.sh","/home/miner/xmrig/miner.sh", "miner")
		remote("chmod +x /home/miner/xmrig/miner.sh","miner")
	end

	def deploy!
		copy("sources.list","/etc/apt/")
		copy("rc.local sysctl.conf", "/etc/") 
		remote("adduser miner --disabled-password --gecos \"\"")
		remote("mkdir /home/miner/.ssh") 
		remote("cp /root/.ssh/authorized_keys /home/miner/.ssh/") 
		remote("mkdir /home/miner/xmrig/")
		remote("chown -R miner:miner /home/miner/")
		copy_binary
		install_miner_config
		remote("apt-get update && apt-get install -y libuv1 libuv-dev libmicrohttpd12 sudo psmisc screen")
		
		no_reboot_route
		#reboot_route
	end
	
	def no_reboot_route
		remote("sysctl -w vm.nr_hugepages=256")
		start_miner
	end

	def reboot_route
		puts "rebooting server... "
		remote("reboot")
	end

	def copy_binary
		copy(binary_path, "/home/miner/xmrig/xmrig", "miner")
	end	

	def update_config!
		install_miner_config	
		restart_miner!	
	end

	def update_miner!
		kill_miner!
		copy_binary
		start_miner
	end

	def restart_miner!
		kill_miner!
		start_miner
	end

	def kill_miner!	
		remote("killall xmrig","miner")
		remote("killall screen","miner")
	end

	def start_miner
		remote("screen -dm -S miner ~/xmrig/miner.sh","miner") 
	end

end
