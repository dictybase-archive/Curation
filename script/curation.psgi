#!/usr/bin/env perl

use strict;
use local::lib '/home/ubuntu/dictyBase/Libs/modern-perl-dapper';
use FindBin;
use Mojo::Server::PSGI;
use Plack::Builder;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../lib";
use lib ('lib','/home/ubuntu/dicty/lib');

print $ENV{PLACK_ENV};

BEGIN {
    $ENV{MOJO_MODE} = $ENV{PLACK_ENV};
};

my $psgi = Mojo::Server::PSGI->new(app_class => 'Curation');
my $app = sub {$psgi->run(@_)};

$app;
