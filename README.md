elb-in-15
=========

Get an AWS ELB going backed by N nodes distributed over all AZs in that region

This sets up a ELB environment  by spawning N instances of Ubuntu 11.04 - these instances are spawned across multiple AZs in the given region and setup with a Apache listening on port 8080 with a simple CGI (for primitive "dynamic" content) and the ELB listening on port 80.

Instructions
============

Make sure you got a recent Ruby and have fog gem installed.

Update aws_creds.yml to to include your AWS Access key ID and Access key secret.
Update :groups to a security group that you have(or create... Allow port 8080 i.e. :instanceport for now. Can block later to explicitly allow amazon-elb alone later).
Run "elbsetup.rb <create|list|destroy> <elbname>" (ELB Name is required for List/Destroy alone.
