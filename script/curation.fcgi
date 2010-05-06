#!/usr/bin/env perl

use strict;
use local::lib '/home/ubuntu/dictyBase/Libs/GB2';
use FindBin;
use Mojo::Server::FastCGI;

use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../lib";
use lib '/home/ubuntu/dicty/lib';

BEGIN { $ENV{ORACLE_HOME} = '/oracle/10g';
	$ENV{DATABASE} = 'DICTYBASE';
	$ENV{CHADO_USER} = 'CGM_CHADO';
	$ENV{CHADO_PW} = 'CGM_CHADO';
};

my $fcgi = Mojo::Server::FastCGI->new(app_class => 'Curation');
$fcgi->run;

