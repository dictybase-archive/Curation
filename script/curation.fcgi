#!/usr/bin/env perl

use strict;
use local::lib '/home/ubuntu/dictyBase/Libs/gb2';
use FindBin;
use Mojo::Server::FastCGI;

use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../lib";
use lib '/home/ubuntu/dicty/lib';

BEGIN { $ENV{ORACLE_HOME} = '/oracle/10g';
	$ENV{DATABASE} = 'DICTYBASE';
	$ENV{CHADO_USER} = 'CGM_CHADO';
	$ENV{CHADO_PW} = 'CGM_CHADO';
	$ENV{USER} = 'CGM_DDB';
	$ENV{PASSWORD} = 'CGM_DDB';
	$ENV{DBUSER} = 'CGM_DDB';
	$ENV{DBUID} = 'CGM_DDB/rctdwak@DICTYBASE';
	$ENV{CHADO_UID} = 'CGM_CHADO/th0mp50n@DICTYBASE';
};

my $fcgi = Mojo::Server::FastCGI->new(app_class => 'Curation');
$fcgi->run;

