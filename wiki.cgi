#!/usr/bin/perl -w
use strict;
use warnings;
use CGI;
use CGI::Wiki::Kwiki;

my %config = (

    # these two will almost certainly need changing.
    db_name => 'cgi-wiki',
    db_user => 'root',

    formatter_type => 'Default', # change to 'Kwiki' for Kwiki formatting.
    template_path => "./templates",
);


# Probably don't need to touch below here.

my %vars = CGI::Vars();

# certain actions are the result of button presses.
$vars{action} = 'commit' if $vars{commit};
$vars{action} = 'preview' if $vars{preview};

# It's possible to pass the node name in more than one way.
$vars{node} ||= CGI::param('keywords');

eval {
    CGI::Wiki::Kwiki->new(%config)->run(%vars);
};

if ($@) {
    print "Content-type: text/plain\n\n";
    print "There was a problem with CGI::Wiki::Kwiki:\n\n--\n";
    print "$@";
    print "\n--\n";
    print STDERR $@;
}
