elb-in-15
=========

Get an AWS ELB going backed by N nodes distributed over all AZs in that region...

This sets up a ELB environment  by spawning N instances of Ubuntu 11.04 - these instances are spawned across multiple AZs in the given region and setup with a Apache listening on port 8080 with a simple CGI (for primitive "dynamic" content) and the ELB listening on port 80.

Instructions
============

1. Make sure you got a recent Ruby and have fog gem installed.
2. Update aws_creds.yml to to include your AWS Access key ID (`:aws_access_key_id`) and Access key secret(`:aws_secret_access_key`)
3. Update `:groups` to a security group that you have(or create... Allow port `:instanceport` for now. Can block later to explicitly allow amazon-elb alone later).
4. Run "elbsetup.rb <create|list|destroy> <elbname>" (ELB Name is required for List/Destroy alone) - `Destroy` will not ask for confirmation :-)
