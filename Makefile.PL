    use ExtUtils::MakeMaker;
    WriteMakefile
      ('DISTNAME' => 'CGI-Wiki-Kwiki',
       'VERSION' => '0.2',
       'PL_FILES' => {},
       'PREREQ_PM' => {
			'Getopt::Long' => '0',
			'CGI::Wiki::Formatter::Kwiki' => '0',
			'Search::InvertedIndex' => '0',
			'Time::Piece' => '0',
			'Test::Simple' => '0',
			'Template' => '0',
			'CGI' => '0',
			'CGI::Kwiki' => '0',
			'CGI::Wiki' => '0.05',

		      },
      );
