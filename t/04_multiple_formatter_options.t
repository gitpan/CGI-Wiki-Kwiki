use warnings;
use strict;
use Test::More;
use CGI::Wiki::Kwiki;
use CGI::Wiki::Setup::SQLite;
use Digest::MD5 qw( md5_hex );

use lib "./t/lib"; # for test formatters

eval { require Test::HTML::Content; require DBD::SQLite; };

if ( $@ ) {
    plan skip_all => "Either Test::HTML::Content or DBD::SQLite not installed";
} else {
    plan tests => 7;

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

    # Test that the edit page offers formatter type option.
    my $output = $wiki->run(
                             return_output => 1,
                             action        => "edit",
                             node          => "New Node",
                           );
    Test::HTML::Content::tag_ok( $output, "select", { name => "formatter" },
                                 "formatter select offered on edit page" );
    Test::HTML::Content::tag_ok( $output, "option", { value => "pony" },
                                 "pony formatter offered as option" );

    # Test it for the preview page too.
    $output = $wiki->run(
                          return_output => 1,
                          action        => "preview",
                          node          => "New Node",
                          checksum      => md5_hex( "" ),
                          content       => "foo",
                          formatter     => "pony",
                        );

    Test::HTML::Content::tag_ok( $output, "select", { name => "formatter" },
                                 "formatter select offered on preview page" );
    Test::HTML::Content::tag_ok( $output, "option",
                                 { value => "pony", selected => "1" },
                                 "pony formatter selected when appropriate" );

    # And check that the right formatter is being used for the preview.
    like( $output, qr|<h2>Preview</h2>\s*PONY|,
          "correct formatter used for preview" );

    $output = $wiki->run(
                          return_output => 1,
                          action        => "preview",
                          node          => "New Node",
                          content       => "foo",
                          formatter     => "pie",
                        );
    Test::HTML::Content::tag_ok( $output, "option",
                                 { value => "pie", selected => "1" },
                                 "pie formatter selected when appropriate" );

    # Now test that the formatter type option isn't offered if there is
    # only one available formatter.
    $wiki = CGI::Wiki::Kwiki->new(
        db_type       => "SQLite",
        db_name       => "./t/wiki.db",
        db_user       => 'foo', # this should be unnecessary!  FIXME
        formatters    => {
                           default => "Local::Test::Formatter::Pony",
                         },
        template_path => './templates',
        search_map    => 't/search_map_2', # different map or SII will complain
    );

    $output = $wiki->run(
                             return_output => 1,
                             action        => "edit",
                             node          => "New Node",
                           );
    Test::HTML::Content::no_tag( $output, "select", { name => "formatter" },
          "no formatter select offered on edit page if only one formatter" );

}
