###############################################################################
# Purpose : Build HTML emails
# Author  : Tony Hennessy
# Created : Aug 2006
###############################################################################

package Email::MIME::CreateHTML;

use strict;
use Carp;
use Exporter;
use Email::MIME;
use HTML::TokeParser::Simple;
use HTML::Tagset;
use Encode::Guess;
use Encode qw' _utf8_on decode ';

our $VERSION = '1.042';

use Email::MIME::CreateHTML::Resolver;

#Globals
use vars qw(%EMBED @EXPORT_OK @ISA);
%EMBED = (
	'bgsound' => {'src'=>1},
	'body'    => {'background'=>1},
	'img'     => {'src'=>1},
	'input'   => {'src'=>1},
	'table'   => {'background'=>1},
	'td'      => {'background'=>1},
	'th'      => {'background'=>1},
	'tr'      => {'background'=>1},
);
@EXPORT_OK = qw(embed_objects parts_for_objects build_html_email);
@ISA = qw(Exporter);

#
# Public routines used by create_html and also exportable
#

sub embed_objects {
	my ($html, $args) = @_;
	my $embed = ( defined $args->{embed} && $args->{embed} eq '0' ) ? 0 : 1;
	my $inline_css = ( defined $args->{inline_css} && $args->{inline_css} eq '0' ) ? 0 : 1;
	my $resolver = new Email::MIME::CreateHTML::Resolver($args);
	my $embed_tags = $args->{'embed_elements'} || \%EMBED;
	
	return ($html, {}) unless ( $embed || $inline_css ); #No-op unless one of these is set

	my ($html_modified, %embedded_cids);
	my $parser = HTML::TokeParser::Simple->new( \$html );
	my $regex = '^(' . join('|',keys %HTML::Tagset::linkElements) . ')';
	$regex = qr/$regex/;
	while ( my $token = $parser->get_token ) {

		unless ( $token->is_start_tag( $regex ) ) {
			$html_modified .= $token->as_is;
			next;
		}
		my $token_tag = $token->get_tag();
		my $token_attrs = $token->get_attr();

		# inline_css
		if ( $token_tag eq 'link' && $token_attrs->{type} eq 'text/css' ) {
			unless ( $inline_css ) {
				$html_modified .= $token->as_is;
				next;
			}
			my $link = $token_attrs->{'href'};
			my ($content,$filename,$mimetype,$encoding) = $resolver->get_resource( $link );
			$html_modified .= "\n".'<style type="text/css">'."\n".'<!--'."\n".
							  $content.
							  "\n-->\n</style>\n";
			next;
		}

		# rewrite and embed
		for my $attr ( @{ $HTML::Tagset::linkElements{$token_tag} } ) {
			if ( defined $token_attrs->{$attr} ) {
				my $link = $token_attrs->{$attr};
				next if ($link =~ m/^cid:/i);

				# embed
				if ( $embed && $embed_tags->{$token_tag}->{$attr} ) {
					unless ( defined $embedded_cids{$link} ) {
						# make a unique cid
						my $newcid = time().$$.int(rand(1e6));
						$embedded_cids{$link} = $newcid;
					}
					my $link_rewrite = "cid:".$embedded_cids{$link};
					$token->set_attr( $attr => $link_rewrite );
				}
			}
		}
		$html_modified .= $token->as_is;
	}

	my %objects = reverse %embedded_cids; #invert mapping
	return ($html_modified, \%objects);
}

sub parts_for_objects {
	my ($objects, $args) = @_;
	my $resolver = new Email::MIME::CreateHTML::Resolver($args);

	my @html_mime_parts;
	foreach my $cid (keys %$objects) {
		croak "Content-Id '$cid' contains bad characters" unless ($cid =~ m/^[\w\-\@\.]+$/);
		croak "Content-Id must be given" unless length($cid);
	
		my $path = $objects->{$cid};
		my ($content,$filename,$mimetype,$encoding) = $resolver->get_resource( $path );
	
		$mimetype ||= 'application/octet-stream';
		my $newpart = Email::MIME->create(
			attributes => {
				content_type => $mimetype,
				encoding => $encoding,
				disposition => 'inline', # maybe useful rfc2387
				charset => undef,
				name => $filename,
			},
			body => $content,
		);
		$newpart->header_set('Content-ID',"<$cid>");
#		$newpart->header_set("Content-Transfer-Encoding", "base64");
		push @html_mime_parts , $newpart;
	}
	return @html_mime_parts;
}

# ( $string, $status ) = _normalize_to_perl_string( $string, $encoding )
#
# Tries (no guarantee) to ensure that the string passed in becomes a
# decoded perl unicode string; i.e. not an encoded sequence of octets.
#
# In the optimal case the given string already is a decoded perl unicode string
# (or ascii), in which case it simply returns it with an undef status.
#
# If not, it tries to make it a decoded perl unicode string, and
# returns the status as well to explain what it thinks the string was.

sub _normalize_to_perl_string {
	my ($string, $encoding) = @_;
	if(ref(my $enc = guess_encoding $string)) { # tests ascii and utf8.
		# Need to accept UTF8 without even checking what the target encoding was,
		# as the input may correctly be a decoded perl unicode string, but
		# the target for the email may be some other encoding.
		my $backup = $string;
		_utf8_on $string; # NOP on decoded perl unicode or ascii strings.
		                  # Upgrades encoded utf8 bytes to perl unicode string.
		my $status = $string ne $backup ? "bytes in utf8 encoding" : undef;
		return ($string, $status);
	}
	if(ref(my $enc = guess_encoding $string, $encoding)) {
		# This may result in false-positive recognitions of one encoding as another,
		# but given that it would have resulted in a double-encoded string in
		# the email anyhow, it doesn't make the situation worse, and it causes
		# a warning.
		return ($enc->decode($string), "bytes in ".$enc->name." encoding");
	}
	# Encode::Guess can only work with small preset lists, and honestly,
	# if the string is encoded, not utf8 AND not in the encoding passed
	# to the function, then there's little useful to do but warn about it.
	return ($string, "bytes in unknown encoding instead of $encoding");
}

sub _normalize_and_warn {
	my ($string, $encoding) = @_;
	($string, my $status) = _normalize_to_perl_string($string, $encoding);
	carp "created email may be corrupt, body was not a decoded perl unicode string, but: $status" if $status;
	return $string;
}

sub build_html_raw_email { _build_html_email(@_, body => 0) }

sub build_html_str_email { _build_html_email(@_, body_str => 0) }

sub build_html_email { _build_html_email(@_, body_str => 1) }

sub _build_html_email {
	my($header, $html, $body_attributes, $html_mime_parts, $plain_text_mime, $body_type, $do_normalize) = @_;

	$body_attributes->{charset} = 'UTF-8' unless exists $body_attributes->{charset};
	$body_attributes->{encoding}= 'quoted-printable' unless exists $body_attributes->{encoding};

	$html = _normalize_and_warn($html, $body_attributes->{charset}) if $do_normalize;

	my $email;
	if ( ! scalar(@$html_mime_parts) && ! defined($plain_text_mime) ) {
		# HTML, no embedded objects, no text alternative
		$email = Email::MIME->create(
			header => $header,
			attributes => $body_attributes,
			$body_type => $html,
		);
	}
	elsif ( ! scalar(@$html_mime_parts) && defined($plain_text_mime) ) {
		# HTML, no embedded objects, with text alternative
		$email = Email::MIME->create(
			header => $header,
			attributes => {content_type=>'multipart/alternative'},
			parts => [
				$plain_text_mime,
				Email::MIME->create(
					attributes => $body_attributes,
					$body_type => $html,
				),
			],
		);
	}
	elsif ( scalar(@$html_mime_parts) && ! defined($plain_text_mime) ) {
		# HTML with embedded objects, no text alternative
		$email = Email::MIME->create(
			header => $header,
			attributes => {content_type=>'multipart/related'},
			parts => [
				Email::MIME->create(
					attributes => $body_attributes,
					$body_type => $html,
				),
				@$html_mime_parts,
			],
		);
	}
	elsif ( scalar(@$html_mime_parts) && defined($plain_text_mime) ) {
		# HTML with embedded objects, with text alternative
		$email = Email::MIME->create(
			header => $header,
			attributes => {content_type=>'multipart/alternative'},
			parts => [
				$plain_text_mime,
				Email::MIME->create(
					attributes => {content_type=>'multipart/related'},
					parts => [
						Email::MIME->create(
							attributes => $body_attributes,
							$body_type => $html,
						),
						@$html_mime_parts,
					],
				),
			],
		);
	}
	return $email;
}

sub create { _create_html(@_) }

sub _create_html {
	my (undef, %args) = @_;

	#Argument checking/defaulting
	croak "You can only supply either body_str or body, not both" if $args{body_str} && $args{body};
	croak "You can only supply either text_body_str or text_body, not both" if $args{text_body_str} && $args{text_body};
	my $html = $args{body_str} || $args{body} || croak "You must supply either body_str or body";
	my $objects = $args{'objects'} || undef;
	
	# Make plain text Email::MIME object, we will never use this alone so we don't need the headers
	my $encoding = $args{body_attributes}{charset} || 'UTF-8';
	my $plain_text_mime;
	if ( my $text = $args{text_body_str} || $args{text_body} ) {
		my %text_body_attributes = ( content_type=>'text/plain', encoding => 'quoted-printable', %{$args{text_body_attributes} || {}} );
		my $text_encoding = $text_body_attributes{charset} ||= $encoding;
		$text = decode $text_encoding, $text, 1 if $args{body_type_unknown} || $args{text_body};
		$plain_text_mime = Email::MIME->create(attributes => \%text_body_attributes, body_str => $text);
	}

	# Parse the HTML and create a CID mapping for objects to embed
	# The HTML parser requires a decoded perl unicode string, so we munge that ahead of time
	$html = $args{body_type_unknown} ? _normalize_and_warn( $html, $encoding )    #
		: $args{body} ? decode $encoding, $html, 1 : $html;                         #
	($html, my $embedded_cids) = embed_objects($html, \%args);

	# Create parts for each embedded object
	my @html_mime_parts;
	push @html_mime_parts, parts_for_objects($objects, \%args) if ($objects);
	push @html_mime_parts, parts_for_objects($embedded_cids, \%args) if(%$embedded_cids);

	# Create the mail
	my $header = $args{header};
	my %body_attributes = ( (content_type=>'text/html'), %{$args{body_attributes} || {}});
	my $email = build_html_str_email($header, $html, \%body_attributes, \@html_mime_parts, $plain_text_mime);
	return $email;
}

# Add to Email::MIME
package # Hide from PAUSE
  Email::MIME;

use strict;
use Carp;

sub create_html { Email::MIME::CreateHTML::_create_html(@_, body_type_unknown => 1) }

#Log::Trace stubs
sub DUMP {}
sub TRACE {}

1;

__END__

=pod

=head1 NAME

Email::MIME::CreateHTML - Multipart HTML Email builder

=head1 SYNOPSIS

	use Email::MIME::CreateHTML;
	my $email = Email::MIME::CreateHTML->create(
		header => [
			From => 'my@address',
			To => 'your@address',
			Subject => 'Here is the information you requested',
		],
		body_str => $html,
		text_body_str => $plain_text
	);

	use Email::Send;
	my $sender = Email::Send->new({mailer => 'SMTP'});
	$sender->mailer_args([Host => 'smtp.example.com']);
	$sender->send($email);
  
=head1 DESCRIPTION

This module allows you to build HTML emails, optionally with a text-only alternative and embedded media objects. 
For example, an HTML email with an alternative version in plain text and with all the required
images contained in the mail.

The HTML content is parsed looking for embeddable media objects.   A resource loading routine is used to fetch content
from those URIs and replace the URIs in the HTML with CIDs.  The default resource loading routine is deliberately conservative, only allowing resources to be fetched from the local filesystem.  It's possible and relatively straightforward to plug in a custom resource loading routine that can resolve URIs using a broader range of protocols.  An example of one using LWP is given later in the L</COOKBOOK>.

The MIME structure is then assembled, embedding the content of the resources where appropriate.  Note that this module does not send any mail, it merely does the work of  building the appropriate MIME message.  The message can be sent with L<Email::Send> or any other mailer that can be fed a string representation of an email message.

=head2 Mail Construction

The mail construction is compliant with rfc2557.

HTML, no embedded objects (images, flash, etc), no text alternative

  text/html

HTML, no embedded objects, with text alternative

  multipart/alternative
	  text/plain
	  text/html

HTML with embedded objects, no text alternative

  multipart/related
	  text/html
	  embedded object one
	  embedded object two
	  ...

HTML with embedded objects, with text alternative

  multipart/alternative
	  text/plain
	  multipart/related
		  text/html
		  embedded object one
		  embedded object two
		  ...

=head1 METHODS

=over 4

=item Email::MIME::CreateHTML->create(%parameters)

This method creates an Email::MIME object from a set of named parameters. Of
these the C<header> is mandatory and C<body_str> or C<body> must be present. All
others are optional. See the L</PARAMETERS> section for more information.

=item Email::MIME->create_html(%parameters)

This method is provided only for backwards compatibility. It accepts the C<body>
parameter in either encoded octets or a decoded perl unicode string and tries to
guess which it is. This can lead to corrupted emails. C<text_body> is required
by this method to be an encoded octet sequence in either the charset configured
in C<text_body_attributes>, C<body_attributes> or UTF-8.

Please replace it with the call above.

As it only exists to not break older uses of this module, not all the
functionality documented under L</PARAMETERS> will work with this call.

=back

=head2 LOW-LEVEL API

Email::MIME::CreateHTML also defines a lower-level interface of 3 building-block routines that you can use for finer-grain construction of HTML mails.
These may be optionally imported:

	use Email::MIME::CreateHTML qw(embed_objects parts_for_objects build_html_mail);

=over 4

=item ($modified_html, $cid_mapping) = embed_objects($html, \%options)

This parses the HTML and replaces URIs in the embed list with a CID.
The modified HTML and CID to URI mapping is returned.
Relevant parameters are:

	embed
	inline_css
	base
	object_cache
	resolver

The meanings and defaults of these parameters are explained below.

=item @mime_parts = parts_for_objects($cid_mapping, \%options)

This creates a list of Email::MIME parts for each of the objects in the supplied CID mapping.
Relevant options are:

	base
	object_cache
	resolver

The meanings and defaults of these parameters are explained below.

=item $email = build_html_str_email(\@headers, $html, \%body_attributes, \@html_mime_parts, $plain_text_mime)

=item $email = build_html_raw_email(\@headers, $html, \%body_attributes, \@html_mime_parts, $plain_text_mime)

=item $email = build_html_email(\@headers, $html, \%body_attributes, \@html_mime_parts, $plain_text_mime)

The assembles a ready-to-send Email::MIME object (that can be sent with Email::Send).
C<$plain_text_mime> is required to be an Email::MIME object.

C<build_html_str_email> expects C<$html> to be a decoded perl unicode string.
C<build_html_raw_email> expects C<$html> to be an encoded octet sequence.
C<build_html_email> is provided for backwards compatibility reasons and will
attempt to guess which of the previous two scalar types C<$html> is.

=back

=head1 PARAMETERS

=over 4

=item header =E<gt> I<list>

A list reference containing a set of headers to be created.
If no Date header is specified, one will be provided for you based on the
gmtime() of the local machine.

=item body_str =E<gt> I<scalar>

=item body =E<gt> I<scalar>

A scalar value holding the HTML message body.

C<body_str> expects a decoded perl unicode string.

C<body> expects an encoded octed sequence. During email construction this will
be decoded, using either the charset provided in C<body_attributes> or UTF-8.

=item body_attributes =E<gt> I<hash reference>

This is passed as the attributes parameter to the C<Email::MIME->create> method that creates the html part of the mail.
The body content-type will be set to C<text/html> unless it is overidden here.

=item embed =E<gt> I<boolean>

Attach relative images and other media to the message. This is enabled by default.
The module will attempt to embed objects defined by C<embed_elements>.
Note that this option only affects the parsing of the HTML and will not affect the C<objects> option.

The object's URI will be rewritten as a Content ID.

=item embed_elements =E<gt> I<reference to hash of hashes with boolean values>

The set of elements that you want to be embedded.  Defaults to the C<%Email::MIME::CreateHTML::EMBED> package global.
This should be a data structure of the form:

	embed_elements => {
		$elementname_1 => {$attrname_1 => $boolean_1},
		$elementname_2 => {$attrname_2 => $boolean_2},
		...
	}

i.e. resource will be embedded if C<$embed_elements-E<gt>{$elementname}-E<gt>{$attrname}> is true.

=item resolver =E<gt> I<object>

If a resolver is supplied this will be used to fetch the resources that are embedded as MIME objects in the email.  If no resolver is given the default behaviour is to choose the best available resolver to read C<$uri> with any C<$base> value prefixed.
Resources fetched using the resolver will be cached if an C<object_cache> is supplied.

=item base =E<gt> I<scalar>

This must be a filepath or a URI.

If C<embed> is true (the default) then C<base> will be used when fetching the objects.

Examples of good bases:

  ./local/images
  /home/somewhere/images
  http://mywebserver/images

=item inline_css =E<gt> I<boolean>

Inline any CSS external CSS files referenced through link elements. Enabled by default. 
Some mail clients will only interpret css if it is inlined.

=item objects =E<gt> I<hash reference>

A reference to a hash of external objects. Keys are Content Ids
and the values are filepaths or URIs used to fetch the resource with the resolver. We use C<MIME::Types> to derive the type from the 
file extension. For example in an HTML mail you would use the file keyed on '12345678@bbc.co.uk' like C<E<lt>img src="cid:12345678@bbc.co.uk" alt="a test" width="20" height="20" /E<gt>>

=item object_cache =E<gt> I<cache object>

A cache object can be supplied to cache external resources such as images.
This must support the following interface:

	$o = new ...
	$o->set($key, $value)
	$value = $o->get($key)

Both the Cache and Cache::Cache distributions on CPAN conform to this.


=item text_body_str =E<gt> I<scalar>

=item text_body =E<gt> I<scalar>

A scalar value holding the contents of an additional I<plain text> message body.

C<text_body_str> expects a decoded perl unicode string.

C<text_body> mirrors the behavior of the body string, that is if the body string
is passed: via C<body_str>, C<text_body> is expected to be a decoded perl
unicode string; via C<body>, C<text_body> is expected to be an encoded octet
sequence in either the charset configured in C<text_body_attributes>,
C<body_attributes> or UTF-8, depending on which of these parameters were given.

=item text_body_attributes =E<gt> I<hash reference>

This is passed as the attributes parameter to the C<Email::MIME->create> method that creates the plain text part of the mail.
The body Content-Type will be set to C<text/plain> unless it is overidden here.

=back

=head1 GLOBAL VARIABLES

=over 4

=item %Email::MIME::CreateHTML::EMBED

This is the default set of elements (and the relevant attributes that point at a resource) that will be embedded.
The for this is:

	'bgsound' => {'src'=>1},
	'body'    => {'background'=>1},
	'img'     => {'src'=>1},
	'input'   => {'src'=>1},
	'table'   => {'background'=>1},
	'td'      => {'background'=>1},
	'th'      => {'background'=>1},
	'tr'      => {'background'=>1}

You can override this using the C<embed_elements> parameter.

=back

=head1 COOKBOOK

=head2 The basics

This builds an HTML email:

	my $email = Email::MIME::CreateHTML->create(
		header => [
			From => 'my@address',
			To => 'your@address',
			Subject => 'My speedy HTML',
		],
		body_str => $html
	);

If you want a plaintext alternative, include the C<text_body> option:

	my $email = Email::MIME::CreateHTML->create(
		header => [
			From => 'my@address',
			To => 'your@address',
			Subject => 'Here is the information you requested',
		],
		body_str => $html,
		text_body => $plain_text #<--
	);
	
If you want your images to remain as links (rather than be embedded in the email) disable the C<embed> option:

	my $email = Email::MIME::CreateHTML->create(
		header => [
			From => 'my@address',
			To => 'your@address',
			Subject => 'My speedy HTML',
		],
		body_str => $html,
		embed => 0 #<--
	);

=head2 Optimising out HTML parsing

By default, the HTML is parsed to look for objects and stylesheets that need embedding.  
If you are controlling the construction of the HTML yourself, you can use Content Ids as the URIs within your HTML 
and then pass in a set of objects to associate with those Content IDs:

	my $html = qq{
		<html><head><title>My Document</title></head><body>
			<p>Here is a picture:</p><img src="cid:some_image_jpg@bbc.co.uk">
		</body></html>	
	};

You then need to create a mapping of the Content IDs to object filenames:
	
	my %objects = (
		"some_image_jpg@bbc.co.uk" => "/var/html/some_image.jpg"
	);

Finally you need to disable both the C<embed> and C<inline_css> options to turn off HTML parsing, and pass in your mapping: 
	
	my $quick_to_assemble_mime = Email::MIME::CreateHTML->create(
		header => [
			From => 'my@address',
			To => 'your@address',
			Subject => 'My speedy HTML',
		],
		body_str => $html,
		embed => 0,          #<--
		inline_css => 0,     #<--
		objects => \%objects #<--
	);

=head3 Preprocessing templates

If you have for example a personalised newsletter where your HTML will vary slightly from one email to the next, but you don't want to re-parse the HTML each time to re-fetch and attach objects, you can use the C<embed_objects> function to pre-process the template, converting URIs into CIDs:

	use Email::MIME::CreateHTML qw(embed_objects);
	my ($preproc_tmpl_content, $cid_mapping) = embed_objects($tmpl_content);

You can then reuse this and the CID mapping:

	my $template = compile_template($preproc_tmpl_content);
	foreach $newsletter (@newsletters) {
		
		#Do templating
		my $html = $template->process($newsletter);
		
		#Build MIME structure
		my $mime = Email::MIME::CreateHTML->create(
			header => [
				From => $reply_address,
				To => $newsletter->address,
				Subject => 'Weekly newsletter',
			],
			body_str => $html,
			embed => 0,              #Already done
			inline_css => 0,         #Already done
			objects => $cid_mapping  #Here's one we prepared earlier
		);
		
		#Send email
		send_email($mime);
	}

Note that one caveat with this approach is that all possible images that might be used in the template will be attached to the email.  Depending on your template logic, it may be that some are never actually referenced from within the email (e.g. if an image is conditionally displayed) so this may create unnecessarily large emails.
	
=head2 Plugging in a custom resource resolver

A custom resource resolver can be specified by passing your own object to resolver:

	my $mime = Email::MIME::CreateHTML->create(
		header => [
			From => 'my@address',
			To => 'your@address',
			Subject => 'Here is the information you requested',
		],
		body_str => $html,
		base => 'http://internal.foo.co.uk/images/',
		resolver => new MyResolver,         #<--
	);

The object needs to have the following API:
 
 	package MyResolver;
	sub new {
		my ($self, $options) = @_;
		my $base_uri = $options->{base};
		#... YOUR CODE HERE ... (probably want to stash $base_uri in $self)
	}

 	sub get_resource {
		my ($self, $uri) = @_;
		my ($content,$filename,$mimetype,$xfer_encoding);
		#... YOUR CODE HERE ...
		return ($content,$filename,$mimetype,$xfer_encoding);	 		
 	}

where:

	$uri is the URI of the object we are embedding (taken from the markup or passed in via the CID mapping)
	$base_uri is base URI used to resolve relative URIs
	
	$content is a scalar containing the contents of the file
	$filename is used to set the name attribute of the Email::MIME object
	$mimetype is used to set the content_type attribute of the Email::MIME object
	$xfer_encoding is used to set the encoding attribute of the Email::MIME object
	(note this is the suitable transfer encoding NOT a character encoding)
 
=head2 Plugging in different types of object cache

You can use a cache from the Cache::Cache distribution:
	
	use Cache::MemoryCache;
	my $mime = Email::MIME::CreateHTML->create(
		header => \@headers,
		body_str => $html,
		object_cache => new Cache::MemoryCache( { 
			'namespace' => 'MyNamespace',
			'default_expires_in' => 600 
		} )
	);
				 
Or a cache from the Cache distribution:
	
	use Cache::File;
	my $mime = Email::MIME::CreateHTML->create(
		header => \@headers,
		body_str => $html,
		object_cache => Cache::File->new( 
			cache_root => '/tmp/mycache',
			default_expires => '600 sec'
		)
	);

Alternatively you can roll your own.  You just need to define an object with get and set methods:

	my $mime = Email::MIME::CreateHTML->create(
		header => \@headers,
		body_str => $html,
		object_cache => new MyCache() 
	);
	
	package MyCache;	
	our %Cache;
	sub new {return bless({}, shift())}
	sub get {return $Cache{shift()}}
	sub set {$Cache{shift()} = shift()}
	1;
		
=head1 SEE ALSO

Perl Email Project L<http://pep.pobox.com>

L<Email::Simple>, L<Email::MIME>, L<Email::Send>

=head1 TODO

Maybe add option to control the order that the text + html parts appear in the MIME message. 


=head1 AUTHOR

Tony Hennessy and Simon Flack with cookbook + some refactoring by John Alden <cpan _at_ bbc _dot_ co _dot_ uk>
with additional contributions by Ricardo Signes <rjbs@cpan.org> and Henry Van Styn <vanstyn@cpan.org>

=head1 COPYRIGHT

(c) BBC 2005,2006. This program is free software; you can redistribute it and/or modify it under the GNU GPL.

See the file COPYING in this distribution, or http://www.gnu.org/licenses/gpl.txt

=cut
