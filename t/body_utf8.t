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

my @base = ( header => [ From => 'unittest_a@example.co.uk', To => 'mail@mail', Subject => '.' ], body => );

my ( undef, $warn ) = capture { Email::MIME->create_html( @base, $d ) };
like $warn, qr/created email may be corrupt, body was not a decoded perl unicode string, but: bytes in utf8 encoding/, "warns with encoded body";

( undef, $warn ) = capture { Email::MIME->create_html( @base, $c ) };
is $warn, "", "decoded perl unicode string causes no warnings";

done_testing;
