#!/usr/bin/perl 

use strict;
use DBI;
use IO::File;
use Getopt::Long;
use File::Spec::Functions;
use DateTime::Format::Strptime;

my ( $help, $dbfile, $source);

GetOptions(
    'h|help'    => \$help,
    'd|database=s' => \$dbfile,
    's|source=s'   => \$source
);
pod2usage( -verbose => 2 ) if $help;
die 'no database filename provided' if !$dbfile;

my $dbh = DBI->connect( "dbi:SQLite:dbname=$dbfile", '', '' );
$dbh->{AutoCommit} = 1;

die 'no source folder provided' if !$source;
my @tables = ( 'stats', 'curation_stats' );

my $parser = DateTime::Format::Strptime->new(pattern => '%b-%d-%Y');

foreach my $table (@tables) {
    my $filename =  catfile( $source, $table );
    die 'source folder does not have source file: ' . $table
        if !-e $filename;
        
    my $fh = IO::File->new($filename, 'r');
    my $line = $fh->getline;
    my @header = split("\t", $line);
    my $val_count = scalar @header;
    my $placeholders = join ',', map { '?' } @header;
    
    my $insert_sql = qq{
        insert into $table values($placeholders)
    };
    my $sth = $dbh->prepare($insert_sql);
    while ( my $line = $fh->getline ) {
        chomp $line;
        my ( $id, $date, @values ) =
            map { $_ eq 'n/a' ? undef : $_ } split( "\t", $line, $val_count );

        my $parsed_date =
            $parser->parse_datetime(uc $date)->strftime('%Y-%m-%d');
        $sth->execute( $id, $parsed_date, @values );
    }
};
