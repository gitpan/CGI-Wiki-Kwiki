use warnings;
use strict;
use Test::More tests => 6;
use CGI::Wiki::Kwiki;
use CGI::Wiki::Setup::SQLite;

eval { require DBD::SQLite; require IO::Scalar; };
my $run_tests = $@ ? 0 : 1;

# $wiki->run prints to STDOUT so we need IO::Scalar to capture the output
SKIP: {
    skip "One of DBD::SQLite and IO::Scalar not installed - can't test output",
        6, unless $run_tests;

    # Clear database, instantiate wiki, add some data.
    CGI::Wiki::Setup::SQLite::cleardb( "./t/wiki.db" );
    CGI::Wiki::Setup::SQLite::setup( "./t/wiki.db" );
    my $wiki = CGI::Wiki::Kwiki->new(
        db_type       => "SQLite",
        db_name       => "./t/wiki.db",
        db_user       => 'foo', # this should be unnecessary!  FIXME
        template_path => './templates',
    );
    $wiki->{wiki}->write_node( "Node 1", "This is Node 1", undef,
                               { username => "Kake", comment => "foobar" } );

    my $output1;
    tie *STDOUT, 'IO::Scalar', \$output1;
    eval {
        $wiki->run(
                    username => "Kake",
                    action   => "userstats",
                  );
    };
    untie *STDOUT;

    is( $@, "", "userstats action is supported" );
    like( $output1, qr/Node 1/, "...and gets the node name" );
    like( $output1, qr/foobar/, "...and gets the comment" );
    like( $output1, qr/Last\s+node\s+edited\s+by/,
          "...number of nodes correct when 1 node found" );

    $wiki->{wiki}->write_node( "Node 2", "This is Node 2", undef,
                               { username => "Kake", comment => "foobar" } );

    my $output2;
    tie *STDOUT, 'IO::Scalar', \$output2;
    eval {
        $wiki->run(
                    username => "Kake",
                    action   => "userstats",
                  );
    };
    untie *STDOUT;

    like( $output2, qr/Last\s+2\s+nodes\s+edited\s+by/,
          "...number of nodes correct when 2 nodes found" );

    my $output3;
    tie *STDOUT, 'IO::Scalar', \$output3;
    eval {
        $wiki->run(
                    username => "Kake",
                    action   => "userstats",
                    n        => 1,
                  );
    };
    untie *STDOUT;

    like( $output3, qr/Last\s+node\s+edited\s+by/,
          "...only returns 1 node when we ask for only 1" );
}
