package CGI::Wiki::Kwiki;

=head1 NAME

CGI::Wiki::Kwiki - An instant wiki built on CGI::Wiki.

=head1 DESCRIPTION

A simple-to-use front-end to L<CGI::Wiki>.  It can be used for several
purposes: to migrate from a L<CGI::Kwiki> wiki (its original purpose),
to provide a quickly set up wiki that can later be extended to use
more of CGI::Wiki's capabilities, and so on.  It uses the L<Template>
Toolkit to allow quick and easy customisation of your wiki's look
without you needing to dive into the code.

=head1 METHODS

=over 4

=item B<new>

Creates a new CGI::Wiki::Kwiki object. Expects some options, most have
defaults, a few are required. Here's how you'd call the constructor -
all values here (apart from C<formatters>) are defaults; the values
you must provide are marked.

    my $wiki = CGI::Wiki::Kwiki->new(
        db_type => 'MySQL',
        db_user => '',
        db_pass => '',
        db_name => undef,                     # required
        db_host => '',
        formatters => {
            documentation => 'CGI::Wiki::Formatter::Pod',
            tests         => 'My::Own::PlainText::Formatter',
            discussion    => [
                               'CGI::Wiki::Formatter::UseMod',
                               allowed_tags   => [ qw( p b i pre ) ],
                               extended_links => 1,
                               implicit_links => 0,
                             ],
            _DEFAULT      => [ # if upgrading from pre-0.4
                               'CGI::Wiki::Formatter::UseMod;
                             ],
                      },                  # example only, not default
        site_name => 'CGI::Wiki::Kwiki site',
        admin_email => 'email@invalid',
        template_path => undef,               # required
        stylesheet_url => "",
        home_node => 'HomePage',
        cgi_path => CGI::url(),
        search_map => './search_map',
    );

The C<db_type> parameter refers to a CGI::Wiki::Store::[type] class.
Valid values are 'MySQL', SQLite', etc: see the L<CGI::Wiki> man page
and any other CGI::Wiki::Store classes you have on your
system. C<db_user> and C<db_pass> will be used to access this
database.

C<formatters> should be a reference to a hash listing all the
formatters that you wish to support.  Different wiki pages can be
formatted with different formatters; this allows you to do things like
have documentation pages written in POD, test suite pages written in
plain text, and discussion pages written in your favourite Wiki
syntax.  If this hash has more than one entry, its keys will be
supplied in a drop-down list on every edit screen, and the selected
one will be used when displaying that page.

(If you I<do> wish to supply more than one entry to the hash, you will
need L<CGI::Wiki::Formatter::Multiple> installed on your system.)

Each value of the C<formatters> hash can be either a simple scalar
giving the class of the required formatter, or an anonymous array
whose first entry is the class name and whose other entries will be
passed through to the formatter instantiation, parsed as a hash.  (See
the C<discussion> formatter entry in the example code above if this
sounds confusing.)

B<Note:> Even if your C<formatters> hash has only one entry, you
should make its key be meaningful, since it will be stored in the
node's metadata and will appear in dropdowns if you ever decide to
support another kind of formatter.

B<Backwards Compatibility Note:> If you are upgrading from a version
of L<CGI::Wiki::Kwiki> earlier than 0.4, and you have an existing wiki
running on it, you should supply a C<_DEFAULT> entry in the
C<formatters> hash so it knows what to do with nodes that have no
formatter metadata stored.

This method tries to create the store, formatter and wiki objects, and will
die() if it has a problem. It is the calling script's responsibility to
catch any exceptions and tell the user.

=item B<run>

Runs the wiki object, and outputs to STDOUT the result, including the CGI
header. Takes no options.

    $wiki->run();

=back

=head1 TODO

Things I still need to do

=over 4

=item Polish templates

=item Import script should catch case-sensitive dupes better

=back

=head1 SEE ALSO

=over

=item *

L<CGI::Wiki>

=item *

L<http://the.earth.li/~kake/cgi-bin/london.crafts/wiki.cgi> - a wiki for a local crafts group, running on CGI::Wiki::Kwiki

=back

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

our $VERSION = '0.44';

my $default_options = {
    db_type => 'MySQL',
    db_user => '',
    db_pass => '',
    db_name => undef,
    db_host => '',
    formatters => {
                    default => [
                                 'CGI::Wiki::Formatter::Default',
                                 allowed_tags => [ qw( p b i pre ) ],
                               ],
                  },
    site_name => 'CGI::Wiki::Kwiki site',
    admin_email => 'email@invalid',
    template_path => undef,
    stylesheet_url => "",
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
        dbhost => $self->{db_host},
    ) or die "Couldn't create store of class $store_class";

    my %formatter_objects;
    while ( my ($label, $formatter) = each %{ $self->{formatters} } ) {
        my $formatter_class = ref $formatter ? shift @$formatter : $formatter;
        eval "require $formatter_class";
        if ( $@ ) {
            die "Couldn't 'use' $formatter_class: $@";
        }
        my %formatter_args = ref $formatter ? @$formatter : ( );
        $formatter_args{node_prefix} = $self->{cgi_path} . "?node=";
        $formatter_args{edit_prefix} = $self->{cgi_path}."?action=edit;node=";

        my $formatter_obj = $formatter_class->new( %formatter_args )
          or die "Can't create formatter object of class $formatter_class";

        $formatter_objects{$label} = $formatter_obj;
    }
    if ( scalar keys %formatter_objects > 1 ) {
        require CGI::Wiki::Formatter::Multiple;
        $self->{formatter} =
                     CGI::Wiki::Formatter::Multiple->new(%formatter_objects );
    } else {
        my ($label, $formatter_object) = each %formatter_objects;
        $self->{formatter} = $formatter_object;
        $self->{formatter_label} = $label;
    }

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
    $self->{return_tt_vars} = delete $args{return_tt_vars} || 0;
    $self->{return_output}  = delete $args{return_output}  || 0;
    my ($node, $action) = @args{'node', 'action'};
    my $metadata = { username  => $args{username},
                     comment   => $args{comment},
                     edit_type => $args{edit_type},
                     formatter => $args{formatter},
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
            my @nodes = sort $self->{wiki}->list_all_nodes();
            $self->process_template( "site_index.tt", "index", { nodes => \@nodes, not_editable => 1 } );
    
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
    my $content = $self->{wiki}->format($raw, $node_data{metadata});
    
    my %tt_vars = (
        content    => $content,
        node_name  => CGI::escapeHTML($node),
        node_param => CGI::escape($node),
        version    => $version,
        metadata   => $node_data{metadata},
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

        %tt_vars = (
                     %tt_vars,
                     recent_changes => \@recent,
                     days           => 7,
                     not_editable   => 1,
                   );
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
        $tt_vars{not_editable} = 1;
        $self->process_template( "wanted_pages.tt", $node, \%tt_vars );

    } else {
        $self->process_template( "node.tt", $node, \%tt_vars );
    }
}


sub preview_node {
    my ($self, $node, $content, $checksum, $metadata) = @_;

    if ( $self->{wiki}->verify_checksum( $node, $checksum ) ) {
        my @formatter_labels = sort keys %{ $self->{formatters} };
        my %tt_vars = (
            content      => CGI::escapeHTML($content),
            preview_html => $self->{wiki}->format($content,
                            { formatter => [ $metadata->{formatter} ] } ),
            checksum     => CGI::escapeHTML($checksum),
            formatter_labels => \@formatter_labels,
            map { $_ => CGI::escapeHTML($metadata->{$_}||"") } keys %$metadata,
        );

        $self->process_template( "edit_form.tt", $node, \%tt_vars );

    } else {
        my %node_data = $self->{wiki}->retrieve_node($node);
        my ( $stored, $checksum ) = @node_data{qw( content checksum )};
        my @formatter_labels = sort keys %{ $self->{formatters} };

        my %tt_vars = (
            checksum    => CGI::escapeHTML($checksum),
            new_content => CGI::escapeHTML($content),
            stored      => CGI::escapeHTML($stored),
            formatter_labels => \@formatter_labels,
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

    my @formatter_labels = sort keys %{ $self->{formatters} };

    my %tt_vars = (
        content          => CGI::escapeHTML($content),
        checksum         => CGI::escapeHTML($checksum),
        version          => $version,
        formatter_labels => \@formatter_labels,
	formatter        => CGI::escapeHTML($data{metadata}{formatter}[0]||""),
                  );

    $self->process_template( "edit_form.tt", $node, \%tt_vars );
}

sub process_template {
    my ($self, $template, $node, $vars, $conf) = @_;

    $vars ||= {};
    $conf ||= {};

    my %tt_vars = (
        %$vars,
        site_name      => $self->{site_name},
        cgi_url        => $self->{cgi_path},
        contact_email  => $self->{admin_email},
        description    => "",
        keywords       => "",
        home_link      => $self->{cgi_path},
        home_name      => "Home",
        stylesheet_url => $self->{stylesheet_url},
        dist_version   => "$VERSION",
    );

    if ($node) {
        $tt_vars{node_name}  = CGI::escapeHTML($node);
        $tt_vars{node_param} = CGI::escape($node);
    }

    if ( $self->{return_tt_vars} ) {
        return %tt_vars;
    }

    my %tt_conf = ( %$conf, INCLUDE_PATH => $self->{template_path} );

    # Create Template object, print CGI header, process template.
    my $tt = Template->new( \%tt_conf );
    my $output = CGI::header();

    die $tt->error
        unless ( $tt->process( $template, \%tt_vars, \$output ) );
    return $output if $self->{return_output};
    print $output;
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
        node         => $node,
        version      => $curr_version,
        history      => \@history,
        not_editable => 1,
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
    my %tt_vars = ( nodes        => \@nodes,
		    username     => CGI::escapeHTML($username),
                    not_editable => 1,
                  );
    $self->process_template("userstats.tt", undef, \%tt_vars);
}
