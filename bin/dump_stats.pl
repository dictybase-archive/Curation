#!/usr/bin/perl 

use strict;
use DBI;
use IO::File;
use Getopt::Long;
use File::Spec::Functions;
use Spreadsheet::WriteExcel::Big;

my ( $help, $dbfile, $output );

GetOptions(
    'h|help'       => \$help,
    'd|database=s' => \$dbfile,
    'o|output=s'   => \$output
);
pod2usage( -verbose => 2 ) if $help;
die 'no database filename provided' if !$dbfile;

my $dbh = DBI->connect( "dbi:SQLite:dbname=$dbfile", '', '' );
$dbh->{AutoCommit} = 1;

my $xls = Spreadsheet::WriteExcel::Big->new($output);

my $tables = [
    {   name    => 'stats',
        columns => [
            { timecreated => 'Date' },
            { curated     => 'Curated gene models' },
            {   curated_incomplete_support =>
                    'Curated gene models, incomplete support'
            },
            { pseudogenes           => 'Pseudogenes' },
            { alternate_transcripts => 'Alternate transcripts' },
            {   comprehensively_annotated => 'Genes comprehencively annotated'
            },
            { basic_annotations      => 'Basic annotations' },
            { genes_descriptions     => 'Genes with descriptions' },
            { gene_name_descriptions => 'Genes with name descriptions' },
            { summary                => 'Genes with summary' },
            {   gene_prodicts =>
                    'Genes with gene product (manual + electronic)'
            },
            { manual_gene_products  => 'Genes with manual gene product' },
            { unknown_gene_product  => 'Genes with "unknown" gene product' },
            { go_annotations        => 'Total GO annotations' },
            { non_iea_go            => 'Non IEA GO' },
            { genes_with_go         => 'Genes with GO' },
            { genes_with_exp        => 'Genes wth EXP' },
            {   fully_go_annotated_genes =>
                    'Fully GO annotated genes, manually, all three aspects'
            },
            {   fully_go_annotated_genes_iea =>
                    'Fully GO annotated genes (incl. IEAs)'
            },
            { strains               => 'Total strains' },
            { genes_wth_strains     => 'Genes with strain(s)' },
            { strains_with_genes    => 'Strains with genes associated' },
            { phenotypes            => 'Total phenotypes' },
            { genes_with_phenotypes => 'Genes with phenotype(s)' },
            { papers_curated        => 'Curated papers' },
            { papers_not_curated    => 'Not yet curated papers' },
            { community_annotations => 'Community annotations' },
        ],
        worksheet  => $xls->add_worksheet('Weekly data'),
        difference => $xls->add_worksheet('Weekly difference data')
    },
    {   name    => 'curation_stats',
        columns => [
            { timecreated           => 'Date' },
            { curator               => 'Curator' },
            { curated               => 'Curated gene models' },
            { pseudogenes           => 'Pseudogenes' },
            { go_annotations        => 'Total GO annotations' },
            { genes_with_go         => 'Genes with GO' },
            { phenotypes            => 'Total phenotypes' },
            { genes_with_phenotypes => 'Genes with phenotype(s)' },
            { strains               => 'Total strains' },
            { genes_wth_strains     => 'Genes with strain(s)' },
            { papers_curated        => 'Curated papers' },
            { summary               => 'Genes with summary' },
            {   comprehensively_annotated => 'Genes comprehencively annotated'
            },
            { basic_annotations => 'Basic annotations' },
        ],
        worksheet  => $xls->add_worksheet('by curator'),
        difference => $xls->add_worksheet('difference by curator')
    }
];

foreach my $table (@$tables) {
    my @header = map { values %$_ } @{ $table->{columns} };

    $table->{worksheet}->write( "A1", \@header );
    $table->{difference}->write( "A1", \@header );
    
    my $row_num = 2;

    my @table_columns = map { keys %$_ } @{ $table->{columns} };
    my $query =
        'select ' . join( ',', @table_columns ) . ' from ' . $table->{name};

    my $sth = $dbh->prepare($query);
    $sth->execute();
    
    my $prev_row;
    while ( my $row = $sth->fetchrow_arrayref ) {
        my $difference = [];
        if ($prev_row) {
            for ( my $i = 0; $i < scalar @$row; $i++ ) {
                if ( @$row[$i] !~ m{^\d} ) {
                    push @$difference, @$row[$i];
                    next;
                }
                my $diff = @$row[$i] - @$prev_row[$i];
                push @$difference, $diff;
            }
            use Data::Dumper;
            print Dumper $difference;
        }
        my @total = ( @$row, @$difference );
        $table->{worksheet}->write( "A$row_num", $row );
        $table->{difference}->write( "A$row_num", $difference );
        $row_num++;
        @$prev_row = @$row;
    }

}
 $xls->close();


