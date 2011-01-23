#!/usr/bin/perl 

use strict;
use DBI;
use IO::File;
use Getopt::Long;
use File::Spec::Functions;

my ( $help, $dbfile, $config );

GetOptions(
    'h|help'       => \$help,
    'd|database=s' => \$dbfile,
    'c|config=s'   => \$config
);
pod2usage( -verbose => 2 ) if $help;
die 'no database filename provided' if !$dbfile;
unlink $dbfile if ( -e $dbfile );

my $dbh = DBI->connect( "dbi:SQLite:dbname=$dbfile", '', '' );
$dbh->{AutoCommit} = 1;

my $create_stats = qq{
    CREATE TABLE stats (
            id integer PRIMARY KEY AUTOINCREMENT NOT NULL,
            timecreated date default current_date not null, 
            curated integer default null,
            curated_incomplete_support integer default null,
            pseudogenes integer default null,
            alternate_transcripts integer default null,
            comprehensively_annotated integer default null,
            basic_annotations integer default null,
            genes_descriptions integer default null,
            gene_name_descriptions integer default null,
            summary integer default null,
            gene_prodicts integer default null,
            manual_gene_products integer default null,
            unknown_gene_product integer default null,
            go_annotations integer default null,
            non_iea_go integer default null,
            genes_with_go integer default null,
            genes_with_exp integer default null,
            fully_go_annotated_genes integer default null,
            fully_go_annotated_genes_iea integer default null,
            strains integer default null,
            genes_wth_strains integer default null,
            strains_with_genes integer default null,
            phenotypes integer default null,
            genes_with_phenotypes integer default null,
            papers_curated integer default null,
            papers_not_curated integer default null,
            community_annotations integer default null
    );
};
$dbh->do($create_stats) or die "DBI::str for $create_stats";

my $create_stats_curation = qq{
    CREATE TABLE curation_stats (
            id integer PRIMARY KEY AUTOINCREMENT NOT NULL,
            timecreated date default current_date not null, 
            curator varchar,
            curated integer default null,
            pseudogenes integer default null,
            go_annotations integer default null,
            genes_with_go integer default null,
            phenotypes integer default null,
            genes_with_phenotypes integer default null,
            strains integer default null,
            genes_wth_strains integer default null,
            papers_curated integer default null,
            summary integer default null,
            comprehensively_annotated integer default null,
            basic_annotations integer default null
    );
};
$dbh->do($create_stats_curation) or die "DBI::str for $create_stats_curation";

