use 5.012;
use strictures;
use utf8;
use Test::More;
use Encode qw' encode ';
use Email::MIME;
use Email::MIME::CreateHTML;
use Capture::Tiny 'capture';

my $f = "abc";
my $c = "Hatsune Miku (Japanese: 初音 ミク ) i";
my $d = encode "UTF-8", $c;
my $e = encode "shiftjis", $c;

for (
    [ $f, $f, "UTF-8" ],    #
    [ $c, $c, "UTF-8" ],
    [ $d, $c, "UTF-8",      "bytes in utf8 encoding" ],
    [ $e, $c, "shiftjis",   "bytes in shiftjis encoding" ],
    [ $e, $e, "big5-hkscs", "bytes in unknown encoding instead of big5-hkscs" ],
  )
{
    my ( $str, $expected, $encoding, $status_expected ) = $_->@*;
    my ( $res, $status ) = Email::MIME::CreateHTML::_normalize_to_perl_string( $str, $encoding );
    is $res,    $expected,        "output";
    is $status, $status_expected, "status";
}

my @core = ( header => [ From => 'unittest_a@example.co.uk', To => 'mail@mail', Subject => '.' ] );
my @base = ( @core, body => );

my ( undef, $warn ) = capture { Email::MIME->create_html( @base, $d ) };
like $warn, qr/created email may be corrupt, body was not a decoded perl unicode string, but: bytes in utf8 encoding/, "warns with encoded body";

( undef, $warn ) = capture { Email::MIME->create_html( @base, $c ) };
is $warn, "", "decoded perl unicode string causes no warnings";

( undef, $warn, my $res ) = capture { Email::MIME::CreateHTML->create( @core, body_str => $c ) };
is $res->body_str, $c, "body didn't get corrupted";
is $warn, "", "decoded perl unicode string causes no warnings";

( undef, $warn, $res ) = capture { Email::MIME::CreateHTML->create( @core, body => $d ) };
is $res->body_str, $c, "body didn't get corrupted";
is $warn, "", "decoded perl unicode string causes no warnings";

( undef, $warn, $res ) = capture { Email::MIME::CreateHTML->create( @core, body => $e, body_attributes => { charset => "shiftjis" } ) };
is $res->body_str, $c, "body didn't get corrupted";
is $warn, "", "decoded perl unicode string causes no warnings";

subtest text_body => sub {
	my @methods= (
		[ "via old create API",
		  sub { Email::MIME->create_html( @core,
				body => $d, body_attributes => { charset => "UTF-8" },
				text_body => $e, text_body_attributes => { charset => "shiftjis" },
		  )},
		],
		[ "via new create API, but use pre-encoded strings like in old API",
		  sub { Email::MIME::CreateHTML->create( @core,
				body => $d, body_attributes => { charset => "UTF-8" },
				text_body => $e, text_body_attributes => { charset => "shiftjis" },
		  )},
		],
		[ "via new create API, with perl unicode strings",
		  sub { Email::MIME::CreateHTML->create( @core,
				body_str => $c, body_attributes => { charset => "UTF-8" },
				text_body_str => $c, text_body_attributes => { charset => "shiftjis" },
		  )},
		],
	);
	for (@methods) {
		my ($name, $sub)= @$_;
		subtest $name => sub {
			( undef, $warn, $res ) = &capture($sub);
			is( ($res->subparts)[0]->body_str, $c, 'text body not corrupted' );
			is( ($res->subparts)[0]->body,     $e, 'text body encoded as shiftjis' );
			is( ($res->subparts)[1]->body_str, $c, 'html body not corrupted' );
			is( ($res->subparts)[1]->body,     $d, 'html body encoded as utf-8' );
		};
	}
};

done_testing;
