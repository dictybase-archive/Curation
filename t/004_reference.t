#!perl

use strict;
use warnings;
use Test::More qw/no_plan/;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::Mojo;
use YAML;
use File::Spec::Functions;

my $conf_file = "$FindBin::Bin/../conf/development.yml";

plan skip_all =>
    "could not find config file ($conf_file)"
    if !-e $conf_file;

my $config = YAML::LoadFile($conf_file);

use_ok 'Curation';

my $t = Test::Mojo->new( app => 'Curation' );
my $id = 1;

$t->get_ok("reference/$id")
    ->status_is( 200, 'successful response for reference' )
    ->content_type_like( qr/html/, 'html response for reference' )
    ->content_like( qr/Genes to link/i, 'Got interface for linking genes' )
    ->content_like( qr/Genes already linked/i, 'Got lnked genes list' )
    ->content_like( qr/<table class="topics">/i, 'Topics table is here' );

my $responce = $t->tx->res->body;

$t->get_ok("reference/pubmed/$id")
    ->status_is( 200, 'successful response for pubmed reference' )
    ->content_type_like( qr/html/, 'html response for pubmed reference' )
    ->content_like( qr/Genes to link/i, 'Got interface for linking genes' )
    ->content_like( qr/Genes already linked/i, 'Got lnked genes list' )
    ->content_like( qr/<table class="topics">/i, 'Topics table is here' );



$bridge->route('reference/:id/')->via('delete')
    ->to('reference#delete');


$bridge->route('reference/:id/gene/:gene_id/')->via('post')
    ->to('reference#link_gene');
$bridge->route('reference/:id/gene/:gene_id/')->via('delete')
    ->to('reference#unlink_gene');

$bridge->route('reference/:id/gene/:gene_id/topics/')->via('get')
    ->to( 'reference#get_topics', format => 'json' );
$bridge->route('reference/:id/gene/:gene_id/topics/')->via('put')
    ->to('reference#update_topics');

## not used any more, moved to bulk update from one-by-one
$bridge->route('reference/:id/gene/:gene_id/topics/')->via('post')
    ->to('reference#add_topic');
$bridge->route('reference/:id/gene/:gene_id/topics/:topic')->via('delete')
    ->to('reference#delete_topic');
