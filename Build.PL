use Module::Build;
my $build = Module::Build->new(
    module_name => 'CGI::Wiki::Kwiki',
    license => 'perl',
    requires => {
        'perl'        => '5.6.0',
        'CGI'         => 0,
        'CGI::Wiki'   => '0.05',
        'CGI::Kwiki'  => 0,
        'CGI::Wiki::Formatter::Kwiki' => 0,
        'Template' => 0,
        'Test::Simple' => 0,
        'Getopt::Long' => 0,
        'Time::Piece' => 0,
        'Search::InvertedIndex' => 0,
    },
    create_makefile_pl => 'traditional',
     script_files => [
         'bin/cgi-wiki-kwiki-install',
         'bin/cgi-wiki-kwiki-import',
     ],
);
$build->create_build_script;

