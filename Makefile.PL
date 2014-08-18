use ExtUtils::MakeMaker;

WriteMakefile(
              NAME          => 'Email::MIME::CreateHTML',
              VERSION_FROM  => 'lib/Email/MIME/CreateHTML.pm',
              PREREQ_PM => {
                Log::Trace => 0,
                Test::Assertions => 0,
                Test::Assertions::TestScript => 0,
                Email::MIME::Creator => 0,
                HTML::TokeParser::Simple => 3.15,
                HTML::Tagset => 0,
                File::Slurp::WithinPolicy => 0,
                MIME::Types => 0,
                Data::Serializer => 0,                
                           },
              ABSTRACT_FROM => 'lib/Email/MIME/CreateHTML.pm',
              AUTHOR        => 'British Broadcasting Corporation',
             );
