package CGI::Wiki::Kwiki;

=head1 NAME

CGI::Wiki::Kwiki

=head1 DESCRIPTION

A simple front-end to CGI::Wiki, including import capability from CGI::Kwiki,
designed as a transition module from a CGI::Kwiki wiki to something a little
more powerful. It provides most of the methods you'd expect from a wiki -
change control and listing, conflict management, database backends, etc.

=head1 METHODS

=over 4

=item B<new>

Creates a new CGI::Wiki::Kwiki object. Expects some options, most have defaults,
a few are required. Here's how you'd call the constructor - all values here are
defaults, the values you must provide are marked.

    my $wiki = CGI::Wiki::Kwiki->new(
        db_type => 'MySQL',
        db_user => undef,                     # required
        db_pass => '',
        db_name => undef,                     # required
        formatter_type => 'Default',
        allowed_tags => ['p','b','i','pre'],
        site_name => 'CGI::Wiki::Kwiki site',
        admin_email => 'email@invalid',
        template_path => undef,               # required
        home_node => 'HomePage',
        cgi_path => CGI::url(),
        search_map => './search_map',
    );

the db_type and formatter_type refer to CGI::Wiki::Store::[type] and
CGI::Wiki::Formatter::[type] classes respectively.

Valid values for db_type are 'MySQL', SQLite', etc, see the CGI::Wiki man
page and any other CGI::Wiki::Store classes you have on your system. db_user
and db_pass will be used to access this database.

Likewise, valid values of formatter_type are 'Default', 'Kwiki', 'POD', etc.
allowed_tags is a list of HTML that is allowed, and is passed to the
formatter object. Not all formatter objects use this information.

This method tries to create the store, formatter and wiki objects, and will
die() if it has a problem. It is the calling script's responsibility to
catch any exceptions and tell the user.

=item B<run>

Runs the wiki object, and outputs to STDOUT the result, including the CGI
header. Takes no options.

    $wiki->run();

=back

-head1 TODO

Things I still need to do

=over 4

=item Polish templates

=item Import script should catch case-sensitive dupes better

=back

=head1 SEE ALSO

CGI::Wiki

=head1 AUTHOR

Tom Insam (tom@jerakeen.org)

=head1 CREDITS

Thanks to Kake for writing CGI::Wiki, and providing the initial patches to
specify store and formatter types in the config. And for complaining at me till
I released things.

=head1 COPYRIGHT

     Copyright (C) 2003 Tom Insam.  All Rights Reserved.

This module is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

use strict;
use warnings;
use CGI;
use CGI::Wiki;
use Search::InvertedIndex;
use CGI::Wiki::Search::SII;
use Template;

our $VERSION = '0.3';

my $default_options = {
    db_type => 'MySQL',
    db_user => undef,
    db_pass => '',
    db_name => undef,
    formatter_type => 'Default',
    allowed_tags => ['p','b','i','pre'],
    site_name => 'CGI::Wiki::Kwiki site',
    admin_email => 'email@invalid',
    template_path => undef,
    home_node => 'HomePage',
    cgi_path => CGI::url(),
    search_map => "./search_map",
};

sub new {
    my $class = shift;
    my $self = bless {}, $class;
    my %args = @_;

    for (keys(%args)) {
        if (exists($default_options->{$_})) {
            $self->{$_} = $args{$_};
        } else {
            die "Unknown option $_";
        }
    }

    for (keys(%$default_options)) {
        $self->{$_} = $default_options->{$_}
            unless defined($self->{$_});
        die "Option '$_' is required" unless defined($self->{$_});
    }

    my $store_class = "CGI::Wiki::Store::$self->{db_type}";
    eval "require $store_class";
    if ( $@ ) {
        die "Couldn't 'use' $store_class: $@";
    }

    $self->{store} = $store_class->new(
        dbname => $self->{db_name},
        dbuser => $self->{db_user},
        dbpass => $self->{db_pass},
    ) or die "Couldn't create store of class $store_class";

    my $formatter_class = "CGI::Wiki::Formatter::$self->{formatter_type}";
    eval "require $formatter_class";
    if ( $@ ) {
        die "Couldn't 'use' $formatter_class: $@";
    }

    $self->{formatter} = $formatter_class->new(
        node_prefix    => "$self->{cgi_path}?node=",
        edit_prefix    => "$self->{cgi_path}?action=edit;node=",
        allowed_tags   => $self->{allowed_tags},
        extended_links => 1,
        implicit_links => 1,
    ) or die "Can't create formatter object of class $formatter_class";

    $self->{indexdb} = Search::InvertedIndex::DB::DB_File_SplitHash->new(
          -map_name  => $self->{search_map},
          -lock_mode => "EX" );
    $self->{search} = CGI::Wiki::Search::SII->new(indexdb => $self->{indexdb});

    $self->{wiki} = CGI::Wiki->new(
        store     => $self->{store},
        formatter => $self->{formatter},
        search    => $self->{search},
    ) or die "Can't create CGI::Wiki object";

    return $self;
}

sub run {
    my ($self, %args) = @_;
    my ($node, $action) = @args{'node', 'action'};
    my $metadata = { username  => $args{username},
                     comment   => $args{comment},
                     edit_type => $args{edit_type},
                   };

    if ($action) {

        if ($action eq 'commit') {
            $self->commit_node($node, $args{content}, $args{checksum},
                               $metadata);
    
        } elsif ($action eq 'preview') {
            $self->preview_node($node, $args{content}, $args{checksum},
                                $metadata);
    
        } elsif ($action eq 'edit') {
            $self->edit_node($node, $args{version});
    
        } elsif ($action eq 'revert') {
            $self->revert_node($node, $args{version});
    
        } elsif ($action eq 'index') {
            my @nodes = $self->{wiki}->list_all_nodes();
            $self->process_template( "site_index.tt", "index", { nodes => \@nodes } );
    
        } elsif ($action eq 'show_backlinks') {
            $self->show_backlinks($node);
    
        } elsif ($action eq 'random') {
            my @nodes = $self->{wiki}->list_all_nodes();
            $node = $nodes[int(rand(scalar(@nodes) + 1)) + 1];
            $self->redirect_to_node($node);
    
        } elsif ($action eq 'list_all_versions') {
            $self->list_all_versions($node);

        } elsif ($action eq 'search') {
            $self->search($args{search});

        } elsif ($action eq 'search_index') {
            $|++;
            print "Content-type: text/plain\n\n";
            for ($self->{wiki}->list_all_nodes()) {            
                print "Indexing $_\n";
                my $node = $self->{wiki}->retrieve_node($_);
                $self->{wiki}->search_obj()->index_node($_, $node);
            }
            print "\n\nindexed all nodes\n";
            exit 0;

        } elsif ($action eq 'userstats') {
            $self->do_userstats( %args );
        } else {
            die "Bad action\n";
        }

    } else {

        if ($args{diffversion}) {
            die "diff not implemented yet\n";
        } else {
            $self->display_node($node, $args{version});
        }

    }
}


sub display_node {
    my ($self, $node, $version) = @_;
    $node ||= $self->{home_node};

    my %data = $self->{wiki}->retrieve_node($node);

    my $current_version = $data{version};
    undef $version if ($version && $version == $current_version);

    my %criteria = ( name => $node );
    $criteria{version} = $version if $version;

    my %node_data = $self->{wiki}->retrieve_node( %criteria );
    my $raw = $node_data{content};
    my $content = $self->{wiki}->format($raw);
    # TODO choose formatter based on node metadata
    
    my %tt_vars = (
        content    => $content,
        node_name  => CGI::escapeHTML($node),
        node_param => CGI::escape($node),
        version    => $version,
    );

    if ( $node eq "RecentChanges" ) {
        my @recent = $self->{wiki}->list_recent_changes( days => 7 );
        @recent = map {
            {
                  name          => CGI::escapeHTML( $_->{name} ),
                  last_modified => CGI::escapeHTML( $_->{last_modified} ),
                  username      => CGI::escapeHTML( $_->{metadata}{username}[0] || "" ),
                  comment       => CGI::escapeHTML( $_->{metadata}{comment}[0] || "" ),
                  edit_type     => CGI::escapeHTML( $_->{metadata}{edit_type}[0] || "" ),
                  url           => "$self->{cgi_path}?node=".CGI::escape( $_->{name} )
            }
        } @recent;
        $tt_vars{recent_changes} = \@recent;
        $tt_vars{days}           = 7;
        $self->process_template( "recent_changes.tt", $node, \%tt_vars );


    } elsif ( $node eq "WantedPages" ) {
        my @dangling = $self->{wiki}->list_dangling_links;
        @dangling = map {
            {
            name => CGI::escapeHTML($_),
            edit_link     => "$self->{cgi_path}?node=".CGI::escape($_).";action=edit",
            backlink_link => "$self->{cgi_path}?node=".CGI::escape($_).";action=show_backlinks"
            }
        } sort @dangling;

        $tt_vars{wanted} = \@dangling;
        $self->process_template( "wanted_pages.tt", $node, \%tt_vars );

    } else {
        $self->process_template( "node.tt", $node, \%tt_vars );
    }
}


sub preview_node {
    my ($self, $node, $content, $checksum, $metadata) = @_;

    if ( $self->{wiki}->verify_checksum( $node, $checksum ) ) {
        my %tt_vars = (
            content      => CGI::escapeHTML($content),
            preview_html => $self->{wiki}->format($content),
            checksum     => CGI::escapeHTML($checksum),
            map { $_ => CGI::escapeHTML($metadata->{$_}||"") } keys %$metadata,
        );

        $self->process_template( "edit_form.tt", $node, \%tt_vars );

    } else {
        my %node_data = $self->{wiki}->retrieve_node($node);
        my ( $stored, $checksum ) = @node_data{qw( content checksum )};
        my %tt_vars = (
            checksum    => CGI::escapeHTML($checksum),
            new_content => CGI::escapeHTML($content),
            stored      => CGI::escapeHTML($stored),
            map { $_ => CGI::escapeHTML($metadata->{$_}||"") } keys %$metadata,
        );
        $self->process_template( "edit_conflict.tt", $node, \%tt_vars );
    }
}

sub edit_node {
    my ($self, $node, $version) = @_;

    my %data = $self->{wiki}->retrieve_node($node);

    my $current_version = $data{version};
    undef $version if ($version && $version == $current_version);

    my %criteria = ( name => $node );
    $criteria{version} = $version if $version;

    my %node_data = $self->{wiki}->retrieve_node( %criteria );
    my ( $content, $checksum ) = @node_data{qw( content checksum )};

    my %tt_vars = (
        content  => CGI::escapeHTML($content),
        checksum => CGI::escapeHTML($checksum),
        version  => $version,
    );

    $self->process_template( "edit_form.tt", $node, \%tt_vars );
}

sub process_template {
    my ($self, $template, $node, $vars, $conf) = @_;

    $vars ||= {};
    $conf ||= {};

    my %tt_vars = (
        %$vars,
        site_name     => $self->{site_name},
        cgi_url       => $self->{cgi_path},
        contact_email => $self->{admin_email},
        description   => "",
        keywords      => "",
        home_link     => $self->{cgi_path},
        home_name     => "Home"
    );

    if ($node) {
        $tt_vars{node_name}  = CGI::escapeHTML($node);
        $tt_vars{node_param} = CGI::escape($node);
    }

    my %tt_conf = ( %$conf, INCLUDE_PATH => $self->{template_path} );

    # Create Template object, print CGI header, process template.
    my $tt = Template->new( \%tt_conf );
    print CGI::header;

    die $tt->error
        unless ( $tt->process( $template, \%tt_vars ) );

}

sub commit_node {
    my ($self, $node, $content, $checksum, $metadata) = @_;

    my $written = $self->{wiki}->write_node( $node, $content, $checksum,
                                             $metadata );

    if ($written) {
        $self->display_node($node);

    } else {
        my %node_data = $self->{wiki}->retrieve_node($node);
        my ( $stored, $checksum ) = @node_data{qw( content checksum )};
        my %tt_vars = (
            checksum    => CGI::escapeHTML($checksum),
            new_content => CGI::escapeHTML($content),
            stored      => CGI::escapeHTML($stored),
            map { $_ => CGI::escapeHTML($metadata->{$_}||"") } keys %$metadata,
        );
        $self->process_template( "edit_conflict.tt", $node, \%tt_vars );
    }
}

sub revert_node {
    my ($self, $node, $version) = @_;

    my %node_data = $self->{wiki}->retrieve_node( name=>$node, version=>$version );
    my %current_node = $self->{wiki}->retrieve_node( $node );

    my $written = $self->{wiki}->write_node( $node, $node_data{content}, $current_node{checksum}, { username => "Auto Revert", comment => "Reverted to version $version" } );

    if ($written) {
        $self->display_node($node);

    } else {
        die "Can't revert node for some reason.\n";
    }
}

sub do_search {
    my ($self, $terms) = @_;

    my %finds   = $self->{wiki}->search_nodes($terms);
    my @sorted  = sort { $finds{$a} cmp $finds{$b} } keys %finds;
    my @results = map {
        {
            url   => CGI::escape($_),
            title => CGI::escapeHTML($_)
        }
    } @sorted;
    my %tt_vars = ( results => \@results );
    $self->process_template( "search_results.tt", "", \%tt_vars );
}

sub redirect_to_node {
    my ($self, $node) = @_;
    print CGI::redirect("$self->{cgi_path}?node=".CGI::escape($node));
    exit 0;
}

sub list_all_versions {
    my ($self, $node) = @_;

    my %curr_data = $self->{wiki}->retrieve_node($node);
    my $curr_version = $curr_data{version};

    my @history;
    for my $version ( 1 .. $curr_version ) {
        my %node_data = $self->{wiki}->retrieve_node(
            name    => $node,
            version => $version
        );
        push @history, {
            version  => $version,
            modified => $node_data{last_modified},
            username => $node_data{metadata}{username}[0],
            comment  => $node_data{metadata}{comment}[0],
        };
    }

    @history = reverse @history;
    my %tt_vars = (
        node    => $node,
        version => $curr_version,
        history => \@history
    );
    $self->process_template("node_history.tt", $node, \%tt_vars );
}

sub show_backlinks {
    my ($self, $node) = @_;

    my @backlinks = $self->{wiki}->list_backlinks( node => $node );
    my @results = map {
        { url   => CGI::escape($_),
          title => CGI::escapeHTML($_)
        }
    } sort @backlinks;

    my %tt_vars = ( results      => \@results,
                    num_results  => scalar @results,
                    not_editable => 1 );

    $self->process_template("backlink_results.tt", $node, \%tt_vars);
}

sub search {
    my ($self, $search) = @_;

    my %results = $self->{wiki}->search_nodes($search);
    my @results = map { $_ }
        ( sort { $results{$a} <=> $results{$b} } keys(%results) );

    my %tt_vars = ( results      => \@results,
                    num_results  => scalar @results,
                    search => $search,
                    not_editable => 1 );

    $self->process_template("search_results.tt", undef, \%tt_vars);
    
    
}

sub do_userstats {
    my ($self, %args) = @_;
    my $username = $args{username};
    my $num_changes = $args{n} || 5;
    die "No username supplied to show_userstats" unless $username;
    my @nodes = $self->{wiki}->list_recent_changes(
        last_n_changes => $num_changes,
        metadata_is    => { username => $username }
    );
    @nodes = map {
        {
          name          => CGI::escapeHTML($_->{name}),
	  last_modified => CGI::escapeHTML($_->{last_modified}),
          comment       => CGI::escapeHTML($_->{metadata}{comment}[0]),
          url           => $self->{cgi_path} . "?node=" . CGI::escape($_->{name}),
        }
                 } @nodes;
    my %tt_vars = ( nodes    => \@nodes,
		    username => CGI::escapeHTML($username),
                  );
    $self->process_template("userstats.tt", undef, \%tt_vars);
}
