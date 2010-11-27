#!perl

use strict;
use warnings;
use Test::More qw/no_plan/;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::Mojo;
use YAML;
use File::Spec::Functions;
use dicty::Search::Gene;

my $conf_file = "$FindBin::Bin/../conf/development.yml";

plan skip_all => "could not find config file ($conf_file)"
    if !-e $conf_file;

my $config = YAML::LoadFile($conf_file);

use_ok 'Curation';

my $t = Test::Mojo->new( app => 'Curation' );

$t->get_ok('/curation')->status_is( 302, 'redirected to login page' );

$t->get_ok('/curation/login')
    ->status_is( 200, 'successful response for login' )
    ->content_type_like( qr/html/, 'html response for login' )
    ->content_like( qr/Username/i,          'got username prompt' )
    ->content_like( qr/<tr class="menu">/i, 'got top menu' );

my $dbfile = catfile( "$FindBin::Bin/../db", $config->{database}->{login} );
my $dbh = DBI->connect( "dbi:SQLite:dbname=$dbfile", '', '' );

my $sql = 'SELECT name, password FROM users;';
my $sth = $dbh->prepare($sql);
$sth->execute;

my ( $name, $password ) = $sth->fetchrow_array;

my $options = {
    password => $password,
    username => $name,
};

$t->post_form_ok( '/curation/usersession', '', $options )
    ->status_is( 302, 'redirect response for usersession' );

$t->get_ok('/curation')
    ->status_is( 200, 'successful response for curation index page' )
    ->content_type_like( qr/html/, 'html response for curation index pahe' )
    ->content_like( qr/$name/i, 'got username displayed' );

my $id = 1;

## get reference by ref_no
$t->get_ok("/curation/reference/$id")
    ->status_is( 200, 'successful response for reference' )
    ->content_type_like( qr/html/, 'html response for reference' )
    ->content_like( qr/Genes to link/i, 'Got interface for linking genes' )
    ->content_like( qr/Genes already linked/i,   'Got lnked genes list' )
    ->content_like( qr/<table class="topics">/i, 'Topics table is here' );

## get reference by pubmed
$t->get_ok("/curation/reference/pubmed/$id")
    ->status_is( 500, 'pubmed reference not found' );

$t->post_ok("/curation/reference/pubmed/$id")
    ->status_is( 302, 'redirect response for just created pubmed reference' );

$t->get_ok("/curation/reference/pubmed/$id")
    ->status_is( 302, 'redirect response for existing pubmed reference' );

my $location = $t->tx->res->headers->location;
$t->get_ok($location)->status_is( 200, 'successful response for reference' )
    ->content_type_like( qr/html/, 'html response for pubmed reference' )
    ->content_like( qr/Genes to link/i, 'Got interface for linking genes' )
    ->content_like( qr/Genes already linked/i,   'Got lnked genes list' )
    ->content_like( qr/<table class="topics">/i, 'Topics table is here' )
    ->content_like( qr/PMID:/i,                  'PubMed is returned' );

## attach gene
my $name = 'test_CURATED';
my ($gene) = dicty::Search::Gene->find(
    -name       => $name,
    -is_deleted => 'false'
);

SKIP: {
    skip 'test data (test_CURATED gene) has to be inserted to proceed', 26
        unless $gene;

    my $gene_id = $gene->primary_id;

    $t->post_ok("$location/gene/$gene_id")
        ->status_is( 200, 'successful response for linking gene' )
        ->content_type_like( qr/text/, 'text response for linking gene' )
        ->content_like( qr/successfully linked/, 'successfully linked gene' );

    ## add topics
    my $topics = '["Adhesion","Signal Transduction"]';

    $t->put_ok( "$location/gene/$gene_id/topics", $topics )
        ->status_is( 200, 'successful response for topics update' )
        ->content_type_like( qr/text/, 'text response for topics update' )
        ->content_like( qr/successfully updated/,
        'successfully updated topics' );

    $t->get_ok("$location/gene/$gene_id/topics")
        ->status_is( 200, 'successful response for topics' )
        ->content_type_like( qr/json/, 'json response for topics' )
        ->content_like( qr/$topics/, 'got previously linked topics' );

    $topics = '["Endocytosis","Mitosis"]';

    $t->put_ok( "$location/gene/$gene_id/topics", $topics )
        ->status_is( 200, 'successful response for topics update' )
        ->content_type_like( qr/text/, 'text response for topics update' )
        ->content_like( qr/successfully updated/,
        'successfully updated topics' );

    $t->get_ok("$location/gene/$gene_id/topics")
        ->status_is( 200, 'successful response for topics' )
        ->content_type_like( qr/json/, 'json response for topics' )
        ->content_like( qr/$topics/, 'got previously linked topics' );

    ## unlink genes
    $t->delete_ok("$location/gene/$gene_id")
        ->status_is( 200, 'successful response for gene deletion' );

}

## delete reference
$t->delete_ok($location)
    ->status_is( 200, 'successful response for reference deletion' );

## get deleted reference by ref_no
$t->get_ok($location)->status_is( 500, 'reference not found' );

$t->get_ok('/curation/logout')->status_is( 302, 'redirected after logout' );
