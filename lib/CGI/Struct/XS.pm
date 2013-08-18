use warnings;
use strict;

package CGI::Struct::XS;

use XSLoader;
use Exporter qw(import);
use Storable qw(dclone);

our $VERSION = 1.01;
our @EXPORT = qw(build_cgi_struct);

XSLoader::load();

1;

__END__

=head1 NAME

CGI::Struct::XS - Build structures from CGI data

=head2 DESCRIPTION

This module is XS implementation of C<CGI::Struct>.
It's fully compatible with C<CGI::Struct>, except for error messages.
C<CGI::Struct::XS> is 3-15 (5-25 with dclone disabled) times faster than original module.
