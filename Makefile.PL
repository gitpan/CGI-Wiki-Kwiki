    use ExtUtils::MakeMaker;
    WriteMakefile
      ('DISTNAME' => 'CGI-Wiki-Kwiki',
       'VERSION' => '0.01',
       'PL_FILES' => {},
       'PREREQ_PM' => {
			'Template' => '0',
			'Time::Piece' => '0',
			'Test::Simple' => '0',
			'CGI::Wiki' => '0',
			'CGI::Kwiki' => '0',
			'CGI' => '0',
			'Getopt::Long' => '0',
			'CGI::Wiki::Formatter::Kwiki' => '0',

		      },
      );
