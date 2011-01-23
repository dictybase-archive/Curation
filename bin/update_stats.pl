#!/usr/bin/perl 

use strict;
use DBI;
use IO::File;
use Getopt::Long;
use File::Spec::Functions;
use dicty::DBH;
use YAML;

my ( $help, $db_file, $conf_file );

GetOptions(
    'h|help'       => \$help,
    'd|database=s' => \$db_file,
    'c|config=s'   => \$conf_file,
);
pod2usage( -verbose => 2 ) if $help;
die 'no database filename provided' if !$db_file;
die 'no config filename provided'   if !$conf_file;

my $config = YAML::LoadFile($conf_file);

my $dbh = DBI->connect( "dbi:SQLite:dbname=$db_file", '', '' );
$dbh->{AutoCommit} = 1;

my $legacy_dbh = dicty::DBH->new();

foreach my $table ( @{ $config->{stats}->{tables} } ) {
    my @columns = @{ $table->{columns} };
    my $group   = $table->{group_by};

    my $insert_hash;

    foreach my $column (@columns) {
        my $query = $column->{sql};
        my $name  = $column->{column};

        next if !$query;

        my $sth = $legacy_dbh->prepare($query);
        $sth->execute;

        if ($group) {
            while ( my $row = $sth->fetchrow_hashref ) {
                $insert_hash->{ $row->{$group} }->{$name} = $row->{'c'};
                $insert_hash->{ $row->{$group} }->{$group} =
                    $row->{$group};
            }
        }
        else {
            my $row = $sth->fetchrow_hashref;
            $insert_hash->{'dummy'}->{$name} = $row->{'c'};
            $sth->finish;
        }
    }

    foreach my $key ( sort keys %$insert_hash ) {
        my $rowset  = $insert_hash->{$key};

        next
            if $rowset->{'curator'}
                && $rowset->{'curator'} !~ m{BOBD|PFEY|PASC|KERRY};

        my @columns = keys %$rowset;
        my @values  = map { $rowset->{$_} } @columns;

        my $placeholders = join ',', map {'?'} @values;
        my $insert_sql =
              'insert into '
            . $table->{table} . ' ('
            . join( ',', @columns )
            . ") values ($placeholders)";
        my $sth = $dbh->prepare($insert_sql);
        $sth->execute(@values);
    }
}

