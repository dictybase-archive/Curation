#!/usr/bin/perl 

use strict;
use DBI;
use IO::File;
use Getopt::Long;
use File::Spec::Functions;
use Spreadsheet::WriteExcel::Big;
use YAML;
use MIME::Lite;
use POSIX qw/strftime/;

my ( $help, $db_file, $conf_file, $output );

GetOptions(
    'h|help'       => \$help,
    'd|database=s' => \$db_file,
    'c|config=s'   => \$conf_file,
    'o|output=s'   => \$output,
);

pod2usage( -verbose => 2 ) if $help;
die 'no database filename provided' if !$db_file;
die 'no config filename provided'   if !$conf_file;
my $date = strftime "%Y-%m-%d", localtime;

my $config = YAML::LoadFile($conf_file);

my $dbh = DBI->connect( "dbi:SQLite:dbname=$db_file", '', '' );
$dbh->{AutoCommit} = 1;

my $xls = Spreadsheet::WriteExcel::Big->new($output);

foreach my $table ( @{ $config->{stats}->{tables} } ) {
    my $stats_total = $xls->add_worksheet( $table->{name} ),
    my $stats_diff  =
        $xls->add_worksheet( $table->{name} . ' (differences)' );

    my @header = map { $_->{name} } @{ $table->{columns} };

    $stats_total->write( "A1", \@header );
    $stats_diff->write( "A1", \@header );

    my $row_num = 2;

    my @columns = map { $_->{column} } @{ $table->{columns} };
    my $query =
        'select ' . join( ',', @columns ) . ' from ' . $table->{table};

    my $sth = $dbh->prepare($query);
    $sth->execute();

    my $stored_row;
    my $stored_row_hash;

    while ( my $row = $sth->fetchrow_hashref ) {
        my $difference = [];
        my @line = map { $row->{$_} } @columns;

        if ( $stored_row || $stored_row_hash ) {
            my $prev_row = $stored_row
                || $stored_row_hash->{ $row->{ $table->{group_by} } };

            for ( my $i = 0; $i < scalar @line; $i++ ) {
                if ( @line[$i] !~ m{^\d+$} ) {
                    push @$difference, @line[$i];
                    next;
                }
                my $diff = @line[$i] - @$prev_row[$i];
                push @$difference, $diff;
            }
        }

        $stats_total->write( "A$row_num", \@line );
        $stats_diff->write( "A$row_num", $difference );

        $row_num++;
        if ( $table->{group_by} ) {
            $stored_row_hash->{ $row->{ $table->{group_by} } } = \@line;
        }
        else {
            @$stored_row = @line;
        }
    }
}
$xls->close();

### Create a new multipart message:
my $msg = MIME::Lite->new(
    From    => 'dictybase@northwestern.edu',
    To      => 'dictybase@northwestern.edu',
    Subject => 'dictyBase curation stats',
    Type    => 'multipart/mixed'
);
$msg->attach(
    Type     =>'TEXT',
    Data     =>"Greetings from dictyBase. Here is the curation statistics as of $date."
);

$msg->attach(
    Type     => 'application/x-excel',
    Path     => $output,
    Filename => 'dictystats.xls',
    Disposition => 'attachment'
);
### use Net:SMTP to do the sending
$msg->send('smtp','lulu.it.northwestern.edu', Debug => 1 );

