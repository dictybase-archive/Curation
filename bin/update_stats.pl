#!/usr/bin/perl 

use strict;
use LWP::Simple;

my $content = get("http://192.168.60.10/curation/stats/update");
die "Couldn't get it!" unless defined $content;
print $content;