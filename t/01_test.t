use warnings;
use strict;
use Test::More tests => 3;
use CGI::Wiki;

use_ok( "CGI::Wiki::Kwiki" );

eval { require DBD::SQLite; };
my $run_tests = $@ ? 0 : 1;

# First just test instantiation - doesn't require output capture
my $wiki;
SKIP: {
    skip "DBD::SQLite not installed - no database to test with", 1
        unless $run_tests;

    $wiki = CGI::Wiki::Kwiki->new(
        db_type       => "SQLite",
        db_name       => "./t/wiki.db",
        db_user       => 'foo', # this should be unnecessary!  FIXME
        template_path => './templates',
    );
    isa_ok( $wiki, "CGI::Wiki::Kwiki" );
}

eval { require DBD::SQLite; require IO::Scalar; };
$run_tests = $@ ? 0 : 1;

# $wiki->run prints to STDOUT so we need IO::Scalar to capture the output
SKIP: {
    skip "One of DBD::SQLite and IO::Scalar not installed - can't test output",
        1, unless $run_tests;
    my $output;
    tie *STDOUT, 'IO::Scalar', \$output;
    $wiki->run;
    untie *STDOUT;

    pass( "ok" );

}
