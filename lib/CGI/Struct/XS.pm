use warnings;
use strict;

package CGI::Struct::XS;

use XSLoader;
use Exporter qw(import);

our $VERSION = 1.01;
our @EXPORT = qw(build_cgi_struct);

XSLoader::load();

1;
