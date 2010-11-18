#!/usr/bin/env perl

use strict;
use local::lib '/home/ubuntu/dictyBase/Libs/modern-perl-dapper';
use FindBin;
use Mojo::Server::PSGI;
use Plack::Builder;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../lib";
use lib ('lib','/home/ubuntu/dicty/lib');

BEGIN { $ENV{ORACLE_HOME} = '/oracle/10g';
	$ENV{DATABASE} = 'DICTYBASE';
	$ENV{CHADO_USER} = 'CGM_CHADO';
	$ENV{CHADO_PW} = 'CGM_CHADO';
	$ENV{USER} = 'CGM_DDB';
	$ENV{PASSWORD} = 'CGM_DDB';
	$ENV{DBUSER} = 'CGM_DDB';
	$ENV{DBUID} = 'CGM_DDB/cgm_ddb@DICTYBASE';
	$ENV{CHADO_UID} = 'CGM_CHADO/cgm_chado@DICTYBASE';
};

my $psgi = Mojo::Server::PSGI->new(app_class => 'Curation');
my $app = sub {$psgi->run(@_)};
$app;
