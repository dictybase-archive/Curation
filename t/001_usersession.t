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

$t->get_ok('curation')
    ->status_is( 302, 'redirected to login page' );
    
$t->get_ok('curation/login')
    ->status_is( 200, 'successful response for login' )
    ->content_type_like( qr/html/, 'html response for login' )
    ->content_like( qr/Username/i, 'got username prompt' )
    ->content_like( qr/<tr class="menu">/i, 'got top menu' );


my $dbfile = catfile( "$FindBin::Bin/../db", $config->{database}->{login} );
my $dbh = DBI->connect( "dbi:SQLite:dbname=$dbfile", '', '' );

my $sql = 'SELECT name, password FROM users;';
my $sth = $dbh->prepare($sql);
$sth->execute;

my ($name, $password) = $sth->fetchrow_array;

my $options = {
    password  => $password,
    username => $name,
};

$t->post_form_ok( 'curation/usersession', '', $options )
    ->status_is( 302, 'redirect response for usersession' );
    
$t->get_ok('curation')  
    ->status_is( 200, 'successful response for curation index page' )
    ->content_type_like( qr/html/, 'html response for curation index pahe' )
    ->content_like( qr/$name/i,  'got username displayed');
