#!/usr/bin/ruby
require 'rubygems'
begin
  require 'json'
  require 'fog'
  require 'yaml'
rescue LoadError 
  abort "Need json, fog and yaml gems"
end
AuthFile='./aws_creds.yml'
UserData='./userdata.sh'
TestUri='/cgi-bin/test.cgi'

def awscreds
  begin
    awscreds=YAML::load(File.open(AuthFile))
     x=awscreds['auth']
    raise "Missing AWS Key ID and secret" unless (x.has_key?(:aws_access_key_id) && x.has_key?(:aws_secret_access_key))
    awscreds['misc']=Hash.new unless awscreds.has_key?('misc') 
    awscreds['misc'][:nodecount]=2 unless awscreds['misc'][:nodecount]
    awscreds['misc'][:elbport]=80 unless awscreds['misc'][:elbport]
    awscreds['misc'][:instanceport] = 8080 unless awscreds['misc'][:instanceport]
    return awscreds
  rescue Exception => e
    abort "Oops, maybe #{AuthFile} is missing/unreadable? : #{e.inspect}" 
  end
end

def get_azs(thisec2obj)
  azlist=thisec2obj.describe_availability_zones.body['availabilityZoneInfo'].map {|az| az['zoneName'] }
  abort "Invalid Region #{region} - has no AZs?" if azlist.length <=0 
  return azlist.sort!
end

def parse_userdata(phash=Hash.new) #Does'nt justify using erb for one param... 
  begin
    userdata=File.read(UserData)
    if(phash.keys.length > 0)
      userdata.gsub!(/INSTPORT/m,phash[:instanceport].to_s) if phash.has_key?(:instanceport)
    end
    return userdata
  rescue Exception => e
    abort "Could'nt read user data from #{UserData}! - #{e.inspect}"
  end  
end

#Grab the instances that backend a given ELB
#E.g. - locate_elb_members(elbobj,'awseb-senchaprodtomcat') => ["i-11111111", "i-22222222"]
def locate_elb_members(thiselbobj=nil,elbname=nil)
  elbdesc={'name'=>nil,'members'=>[] ,'dnsname'=>nil,'ports'=>[]} 
  return elbdesc if thiselbobj.nil? || elbname.nil? #No instances
  
  thiselbobj.describe_load_balancers.body['DescribeLoadBalancersResult']['LoadBalancerDescriptions'].each do |thislb|
    next unless thislb['LoadBalancerName'] == elbname
    elbdesc['members']=thislb['Instances']
    elbdesc['name']=elbname
    elbdesc['dnsname']=thislb['CanonicalHostedZoneName']
    thislb['ListenerDescriptions'].each do |lnr|
          elbdesc['ports'].push(lnr['Listener']['LoadBalancerPort']) 
    end
    break
  end 
  return elbdesc 
end

def spawn_instance(ec2obj=nil,instanceinfo=Hash.new,icount=0,nametagprefix="DUMMY-$$",azlist=Array.new)
  return {'az'=>{},'instances'=>{}} if ec2obj.nil? || instanceinfo.keys.length <= 0
  idlist=Hash.new
  puts "Spawning #{icount} instances of type #{instanceinfo[:flavor_id]} in various AZs"
  azlen=azlist.length
  azhash=Hash.new
  instance_hash=Hash.new 
  icount.times do |ctr|
    name=nametagprefix+"-#{ctr}"
    #Try to distribute the backends across multi AZs if possible.
    whichaz=azlist[ctr%azlen]
    print "\tInstance #{ctr} - Name=#{name} AZ=#{whichaz} Waiting"
    thisinstance=ec2obj.servers.create({:availability_zone => whichaz}.merge!(instanceinfo) )
    #Add a Name tag so I know these from my other in-use instances.
    ec2obj.tags.create :key => 'Name', :value => "#{name}", :resource_id => thisinstance.id
    #we are doing this for few instances, so ok to wait a bit. else just spawn and come bakc later and check if up and procedd.
    thisinstance.wait_for { print "."; ready? }
    puts "OK" 
    azhash[whichaz]=nil
    instance_hash[thisinstance.id] = thisinstance.dns_name
  end
  return { 'az' => azhash, 'instances' => instance_hash } 
end

config=awscreds #Got all keys etc here.
userdata_str=parse_userdata(config['misc'])
config['setup'].merge!({:user_data => "#{userdata_str}"})
#Set some names.
prefixes={'elb'=>'nf15min-'+$$.to_s,'instance'=>'TEST_INSTANCE_'+$$.to_s }

ec2obj=Fog::Compute.new(config['auth'].merge({:provider => 'AWS',:region => config['setup'][:region] }))
elbobj=Fog::AWS::ELB.new(config['auth'])

op = ARGV[0].nil? ? "": ARGV[0].upcase
elbname=ARGV[1]
$stderr.puts "Need ELB name for #{op}!" if (op =~ /^(LIST|DESTROY)$/ && (elbname.nil? || elbname=~/^\s*$/))

AzList=get_azs(ec2obj)

if op == "CREATE"
  #Spawn instances.
  puts "** Create instances & spawn ELB **"
  ilist=spawn_instance(ec2obj,config['setup'],config['misc'][:nodecount],prefixes['instance'],AzList)
  puts "\nInstances spawned were: "+ilist['instances'].to_json 
  if (ilist['instances'].keys.length <=0 )
    abort "No instances created! So no point creating ELB."
  end
  #Set an ELB name
  elbname=prefixes['elb']
  puts "\nCreating ELB #{elbname} to span AZs "+ilist['az'].keys.sort.to_json
  listeners=[
            {
              'Protocol'=>'HTTP',
              'LoadBalancerPort'=>config['misc'][:elbport],
              'InstancePort'=>config['misc'][:instanceport], 
              'InstanceProtocol'=>'HTTP'
    }]
    #Create LB
  lb_create=elbobj.create_load_balancer(ilist['az'].keys,elbname,listeners)
    #Def health check
  elbobj.configure_health_check(elbname,{
        'HealthyThreshold' => 4,
        'Interval' => 15,
        'Target' => 'HTTP:'+config['misc'][:instanceport].to_s+'/',
        'Timeout' => 3,
        'UnhealthyThreshold' => 4
  }) 
  #Add backend instances. 
  lb_populate=elbobj.register_instances(ilist['instances'].keys,elbname)
  
 puts "Added ELB #{elbname} - Public URL #{lb_create.body['CreateLoadBalancerResult']['DNSName']} "
  puts "Hit #{lb_create.body['CreateLoadBalancerResult']['DNSName']}#{TestUri} to test access to this ELB (Once instances are registered)" 
##If you know the elb name, list its pub hostname & instance info
elsif op == "LIST"
  thiselb=locate_elb_members(elbobj,elbname) 
  abort "No such ELB known - #{elbname}" unless thiselb.has_key?('name') && ! thiselb['name'].nil? 
  puts "ELB info: \n"+thiselb.to_json

#Unregister instances from ELB, drop ELB and then drop the instances as well...
elsif op == "DESTROY"
    puts "** Destroy ELB #{elbname} & associated instances **"
    #ELB delete is idempotent but we do want to drop the instances too so get the list first.
    elbdesc=locate_elb_members(elbobj,elbname)  
    abort "No such ELB #{elbname}" if (elbdesc.has_key?('name') && elbdesc['name'].nil?)
    elbdesc['members'].each do |thisnode|
      thisserver=ec2obj.servers.get(thisnode)
      puts "\tDropping #{thisnode} (#{thisserver.flavor_id})"
      thisserver.destroy
      elbobj.deregister_instances([ "#{thisnode}" ], elbname )
    end 

    elbobj.delete_load_balancer("#{elbname}")

else
  puts "Uh oh...I only know to CREATE/LIST/DESTROY... "
end

