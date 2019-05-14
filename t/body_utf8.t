use 5.012;
use strictures;
use utf8;
use Test::More;
use Encode qw' encode ';
use Email::MIME;
use Email::MIME::CreateHTML;
use Capture::Tiny 'capture';

my $ascii_string = "abc";
my $perlstring   = "Hatsune Miku (Japanese: 初音 ミク ) i";
my $encoded_utf8 = encode "UTF-8", $perlstring;
my $encoded_jis  = encode "shiftjis", $perlstring;

for (
	[ $ascii_string, $ascii_string, "UTF-8" ],    #
	[ $perlstring,   $perlstring,   "UTF-8" ],
	[ $encoded_utf8, $perlstring,  "UTF-8",      "bytes in utf8 encoding" ],
	[ $encoded_jis,  $perlstring,  "shiftjis",   "bytes in shiftjis encoding" ],
	[ $encoded_jis,  $encoded_jis, "big5-hkscs", "bytes in unknown encoding instead of big5-hkscs" ],
  )
{
	my ( $str, $expected, $encoding, $status_expected ) = $_->@*;
	my ( $res, $status ) = Email::MIME::CreateHTML::_normalize_to_perl_string( $str, $encoding );
	is $res,    $expected,        "output";
	is $status, $status_expected, "status";
}

my @core = ( header => [ From => 'unittest_a@example.co.uk', To => 'mail@mail', Subject => '.' ] );
my @base = ( @core, body => );

my ( undef, $warn ) = capture { Email::MIME->create_html( @base, $encoded_utf8 ) };
like $warn, qr/created email may be corrupt, body was not a decoded perl unicode string, but: bytes in utf8 encoding/, "warns with encoded body";

( undef, $warn ) = capture { Email::MIME->create_html( @base, $perlstring ) };
is $warn, "", "decoded perl unicode string causes no warnings";

( undef, $warn, my $res ) = capture { Email::MIME::CreateHTML->create( @core, body_str => $perlstring ) };
is $res->body_str, $perlstring, "body didn't get corrupted";
is $warn, "", "decoded perl unicode string causes no warnings";

( undef, $warn, $res ) = capture { Email::MIME::CreateHTML->create( @core, body => $encoded_utf8 ) };
is $res->body_str, $perlstring, "body didn't get corrupted";
is $warn, "", "decoded perl unicode string causes no warnings";

( undef, $warn, $res ) = capture { Email::MIME::CreateHTML->create( @core, body => $encoded_jis, body_attributes => { charset => "shiftjis" } ) };
is $res->body_str, $perlstring, "body didn't get corrupted";
is $warn, "", "decoded perl unicode string causes no warnings";

subtest text_body => sub {
	my @base = ( @core, body_attributes => { charset => "UTF-8" }, text_body_attributes => { charset => "shiftjis" } );
	my @methods = (
		[ { body     => $encoded_utf8, text_body     => $encoded_jis }, "via new create API, with encoded strings", ],
		[ { body_str => $perlstring,   text_body_str => $perlstring },  "via new create API, with perl unicode strings" ],
	);
	for (@methods) {
		my ( $cfg, $name ) = @$_;
		subtest $name => sub {
			( undef, $warn, $res ) = capture {
				Email::MIME::CreateHTML->create( @base, %{$cfg} );
			};
			is( ( $res->subparts )[0]->body_str, $perlstring,   'text body not corrupted' );
			is( ( $res->subparts )[0]->body,     $encoded_jis,  'text body encoded as shiftjis' );
			is( ( $res->subparts )[1]->body_str, $perlstring,   'html body not corrupted' );
			is( ( $res->subparts )[1]->body,     $encoded_utf8, 'html body encoded as utf-8' );
		};
	}
};

done_testing;
