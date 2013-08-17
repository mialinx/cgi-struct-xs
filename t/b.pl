use common::sense;
use Benchmark;
use CGI::Struct ();
use CGI::Struct::XS ();

my %inp = (
    'action' => 'update',
    'p.sys.name' => 'dsfdsfdsf',
    'p.sys.slug' => 'sfsdfs',
    'p.sys.client_id' => 'sdfdsgfdsg',
    'p.urls[]' => ['a', 'b', 'c'],
    'p.media[0].id' => 1,
    'p.media[0].name' => 'asdasd',
    'p.media[0].type' => 'img',
    'p.media[1].id' => 1,
    'p.media[1].name' => 'asdasd',
    'p.media[1].type' => 'img',
    'p.media[2].id' => 1,
    'p.media[2].name' => 'asdasd',
    'p.media[2].type' => 'img',
);

timethese(100000, {
    pp => sub { my @errs; CGI::Struct::build_cgi_struct(\%inp, \@errs, { dclone => 0 }); },
    xs => sub { my @errs; CGI::Struct::XS::build_cgi_struct(\%inp, \@errs, { dclone => 0 }); },
});
