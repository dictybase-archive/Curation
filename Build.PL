#!/usr/bin/perl -w
use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name  => 'Curation',
    license      => 'perl',
    dist_author  => 'Siddhartha Basu <siddhartha-basu@northwestern.edu>',
    dist_version => '0.001',
    requires     => {
        'Mojolicious'            => '1.01',
        'Plack'                  => '0.9941',
        'FCGI::Engine'           => '0.16',
        'YAML'                   => '0.72',
        'Modware'                => '0.001',
        'ModConfig'              => '',
        'Bio::Graphics::Browser' => '1.17',
        'Bio::Root::Version'          => '1.0050021',
        'JSON'                   => '1.00',
        'Digest::MD5'            => '2.51', 
        'dicty::DBH'             => '',
        'dicty::DB::AutoDBI'     => '',
        'dicty::Search::Gene'    => ''
    },
    add_to_cleanup => ['Curation- *'],
    create_readme  => 1,
);

$builder->create_build_script();

