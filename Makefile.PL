    use ExtUtils::MakeMaker;
    WriteMakefile
      ('DISTNAME' => 'CGI-Wiki-Kwiki',
       'VERSION' => '0.31',
       'PL_FILES' => {},
       'PREREQ_PM' => {
			'Getopt::Long' => '0',
			'CGI::Wiki::Formatter::Kwiki' => '0',
			'Search::InvertedIndex' => '0',
			'Time::Piece' => '0',
			'Template' => '0',
			'CGI' => '0',
			'Test::More' => '0',
			'CGI::Kwiki' => '0',
			'CGI::Wiki' => '0.05',

		      },
      );
