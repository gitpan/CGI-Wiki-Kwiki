use warnings;
use strict;
use Test::More;
use CGI::Wiki::Kwiki;
use CGI::Wiki::Setup::SQLite;

use lib "./t/lib"; # for test formatters

eval { require DBD::SQLite; };

if ( $@ ) {
    plan skip_all => "DBD::SQLite not installed";
} else {
    plan tests => 1;

    # Instantiate wiki.
    CGI::Wiki::Setup::SQLite::cleardb( "./t/wiki.db" );
    CGI::Wiki::Setup::SQLite::setup( "./t/wiki.db" );
    my $wiki = CGI::Wiki::Kwiki->new(
        db_type       => "SQLite",
        db_name       => "./t/wiki.db",
        db_user       => 'foo', # this should be unnecessary!  FIXME
        formatters    => {
                           pony     => "Local::Test::Formatter::Pony",
                           pie      => "Local::Test::Formatter::Pie"
                         },
        template_path => './templates',
    );

    # Test that formatter data is written on node save.
    $wiki->run(
                return_output => 1, # be quiet
                action        => "commit",
                node          => "New Node",
                content       => "foo",
                formatter     => "pony",
              );

    my %node_data = $wiki->{wiki}->retrieve_node( "New Node" );
    is( $node_data{metadata}{formatter}[0], "pony", "formatter saved" );
}

