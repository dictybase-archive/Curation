#!/usr/bin/perl -w

use Mojo::Server::PSGI;

my $psgi = Mojo::Server::PSGI->new(app_class => 'yulia');
my $app = sub {$psgi->run(@_)};
