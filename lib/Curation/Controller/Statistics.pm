package Curation::Controller::Statistics;

use warnings;
use strict;
use DateTime::Format::Strptime;

# Other modules:
use base 'Mojolicious::Controller';

sub total {
    my ($self) = @_;
    my $dbh = $self->app->stats_dbh;

    my $config = $self->app->config->{stats};
    my $parser = DateTime::Format::Strptime->new( pattern => '%Y-%m-%d' );

    my $resultset;

    foreach my $table ( @{ $config->{tables} } ) {
        next if $table->{name} ne 'stats';

        my @columns = map { $_->{column} } @{ $table->{columns} };
        my $query =
            'select ' . join( ',', @columns ) . ' from ' . $table->{name};

        my $sth = $dbh->prepare($query);
        $sth->execute;

        while ( my $row = $sth->fetchrow_hashref ) {
            my $time = $row->{timecreated};
            next if !$time;

            my $timestamp = $parser->parse_datetime($time)->hires_epoch;

            foreach my $column ( keys %$row ) {
                my ($name) = map { $_->{name} }
                    grep { $_->{column} eq $column } @{ $table->{columns} };
                next if !$name;

                push @{ $resultset->{$column}->{data} },
                    [ $timestamp * 1000, $row->{$column} ];

                $resultset->{$column}->{label} = $name;
            }
        }
        
    }
    $self->render( json => $resultset );
}

sub update {
    my ($self)     = @_;
    my $config     = $self->app->config->{stats};
    my $dbh        = $self->app->stats_dbh;
    my $legacy_dbh = $self->app->dbh;

    foreach my $table ( @{ $config->{tables} } ) {
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
            my @columns = keys %$rowset;
            my @values  = map { $rowset->{$_} } @columns;

            next
                if $rowset->{'curator'}
                    && $rowset->{'curator'} !~ m{BOBD|PFEY|PASC|KERRY};

            my $placeholders = join ',', map {'?'} @values;
            my $insert_sql =
                  'insert into '
                . $table->{name} . ' ('
                . join( ',', @columns )
                . ") values ($placeholders)";
            my $sth = $dbh->prepare($insert_sql);
            $self->app->log->debug($insert_sql);
            $sth->execute(@values);
        }
    }
    $self->render( text => 'Update completed' );
}

1;
