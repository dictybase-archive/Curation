package Curation::Controller::Reference;

use warnings;
use strict;
use Bio::Biblio;
use Bio::Biblio::IO;
use dicty::Search::Gene;
use Modware::Publication::DictyBase;
use Modware::Publication::Author;

# Other modules:
use base 'Mojolicious::Controller';

sub show {
    my ($self)   = @_;
    my $config   = $self->app->config->{reference};
    my $ref      = $self->get_reference;
    my $genes_rs = $self->get_linked_genes($ref);

    my $curated_rs = $genes_rs->search(
        {   'type_2.name' => 'Curated',
            'cv.name'     => 'dictyBase_literature_topic'
        },
        {   join => {
                'feature_pubs' => { 'feature_pubprops' => { 'type' => 'cv' } }
            }
        }
    );
    my $not_curated_rs = $genes_rs->search(
        {   'type_2.name' => 'Not yet curated',
            'cv.name'     => 'dictyBase_literature_topic'
        },
        {   join => {
                'feature_pubs' => { 'feature_pubprops' => { 'type' => 'cv' } }
            }
        }
    );
    my @linked;
    map { push @linked, $_ } map {
        { id => $_->dbxref->accession, name => $_->name, curated => 1 }
    } $curated_rs->all;

    map { push @linked, $_ } map {
        { id => $_->dbxref->accession, name => $_->name, curated => 0 }
    } $not_curated_rs->all;

    my $author_count = $ref->total_authors;
    my $author_str;
    if ( $author_count == 1 ) {
        $author_str = $ref->get_from_authors(0)->last_name;
    }
    elsif ( $author_count == 2 ) {
        $author_str =
              $ref->get_from_authors(0)->last_name . ' & '
            . $ref->get_from_authors(1)->last_name;
    }
    else {
        my $penultimate = $author_count - 2;
        for my $i ( 0 .. $penultimate ) {
            if ( $i == $penultimate ) {
                $author_str .= $ref->get_from_authors($i)->last_name . ' & ';
                next;
            }
            $author_str .= $ref->get_from_authors($i)->last_name . ', ';
        }
        $author_str .= $ref->get_from_authors(-1)->last_name;
    }

    my $pages = $ref->has_pages ? $ref->pages : undef;
    $pages =~ s/\-\-/\-/ if $pages;

    my $year = $ref->year;
    $year =~ s{-}{ }g if $year;

    $self->stash( linkout      => $config->{linkout} );
    $self->stash( abstract     => $ref->abstract );
    $self->stash( year         => $year ) if $year;
    $self->stash( authors      => $author_str );
    $self->stash( pages        => $pages ) if $pages;
    $self->stash( title        => $ref->title ) if $ref->has_title;
    $self->stash( volume       => $ref->volume ) if $ref->has_volume;
    $self->stash( abbreviation => $ref->abbreviation )
        if $ref->has_abbreviation;
    $self->stash( linked => \@linked );
}

sub get_reference {
    my ($self) = @_;
    my $ref = Modware::Publication::DictyBase->find_by_pubmed_id(
        $self->stash('id') );
    return $ref || $self->create_pubmed;
}

sub create_pubmed {
    my ($self) = @_;
    my $citation =
        Bio::Biblio->new( -access => 'pubmed' )
        ->get_by_id( $self->stash('id') );

    my $source = 'PUBMED';
    my $type   = 'journal_article';

    my $ref =
        Modware::Publication::DictyBase->new( id => $self->stash('id') );

    $ref->source($source);
    $ref->type($type);
    $ref->year( $citation->date ) if $citation->date;
    $ref->title( $citation->title );
    $ref->volume( $citation->volume );
    $ref->status( $citation->status );

    $ref->issue( $citation->issue ) if $citation->issue;
    $ref->journal( $citation->journal->abbreviation )
        if $citation->journal->abbreviation;
    $ref->first_page( $citation->first_page ) if $citation->first_page;
    $ref->last_page( $citation->last_page )   if $citation->last_page;
    $ref->abstract( $citation->abstract );

    #    $ref->full_text_url( $citation->full_text_url );

    my $count = 1;
    for my $person ( @{ $citation->authors } ) {
        $ref->add_author(
            Modware::Publication::Author->new(
                last_name  => $person->lastname,
                suffix     => $person->suffix,
                given_name => $person->initials . ' ' . $person->forename,
                rank       => $count++
            )
        );

    }
    $self->stash( created => 1 );

    #$ref->create;
    return $ref;
}

sub get_linked_genes {
    my ( $self, $ref ) = @_;

    my $schema = $self->app->schema;

    return $schema->resultset('Sequence::Feature')->search(
        {   'pub.uniquename' => $ref->id,
            'type.name'      => 'gene',
            'me.is_deleted'  => 0
        },
        { join => [ 'type', { 'feature_pubs' => 'pub' } ] }
    );
}

sub link_gene {
    my ($self)  = @_;
    my $ref     = $self->get_reference;
    my $gene_id = $self->stash('gene_id');

    my ($gene) = dicty::Search::Gene->find(
        -name       => $gene_id,
        -id         => $gene_id,
        -clause     => 'OR',
        -is_deleted => 'false'
    );
    $self->render(
        text   => 'no gene with name or id ' . $gene_id . ' found',
        status => 500
    ) if !$gene;

    eval { $gene->add_reference($ref); $gene->_update_reference_links; };

    $self->render(
        text => 'error linking reference '
            . $self->stash('id')
            . " with gene $gene_id : $@",
        status => 500
    ) if $@;
    $self->render( text => 'successfully linked '
            . $self->stash('id')
            . " with gene "
            . $gene->name );
}

sub unlink_gene {
    my ($self)  = @_;
    my $ref     = $self->get_reference;
    my $gene_id = $self->stash('gene_id');

    my ($gene) = dicty::Search::Gene->find(
        -name       => $gene_id,
        -id         => $gene_id,
        -clause     => 'OR',
        -is_deleted => 'false'
    );
    $self->render(
        text   => 'no gene with name or id ' . $gene_id . ' found',
        status => 500
    ) if !$gene;

    eval { $gene->remove_reference($ref); $gene->_update_reference_links; };

    $self->render(
        text => 'error unlinking reference '
            . $self->stash('id')
            . " with gene $gene_id : $@",
        status => 500
    ) if $@;
    $self->render( text => 'successfully unlinked '
            . $self->stash('id')
            . " with gene "
            . $gene->name );
}

1;
