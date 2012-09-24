#!/bin/bash

apt-get -y update
apt-get -y install apache2 apache2-mpm-prefork
#Going to assume a debian/ubuntu ami for now to take some paths for granted...

logger -t userdata "Setting up /cgi-bin/test.cgi"
cat - >/usr/lib/cgi-bin/test.cgi <<EOF
#!/usr/bin/perl
use Sys::Hostname;
print "Content-type: text/html\n\n";
print "Host=".hostname().",Time=".time()."\n";
EOF
[ -f /usr/lib/cgi-bin/test.cgi ] && chmod 555 /usr/lib/cgi-bin/test.cgi

logger -t userdata "Updating apache config (quick'n'dirty!)"
perl -p -i -e 's/Listen 80/Listen INSTPORT/' /etc/apache2/ports.conf
perl -p -i -e 's/NameVirtualHost \*:80/NameVirtualHost \*:INSTPORT/' /etc/apache2/ports.conf
perl -p -i -e 's/VirtualHost \*:80/VirtualHost \*:INSTPORT/' /etc/apache2/sites-enabled/*

service apache2 restart
logger -t userdata "Finished"


