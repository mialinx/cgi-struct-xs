use common::sense;
use Benchmark;
use CGI::Struct ();
use CGI::Struct::XS ();

my %inp = (
    'action' => 'update',
    'p_sys_name' => 'dsfdsfdsf',
    'p_sys_slug' => 'sfsdfs',
    'p_sys_client_id' => 'sdfdsgfdsg',
    'p_urls__' => ['a', 'b', 'c'],
    'p_media_0__id' => 1,
    'p_media_0__name' => 'asdasd',
    'p_media_0__type' => 'img',
    'p_media_1__id' => 1,
    'p_media_1__name' => 'asdasd',
    'p_media_1__type' => 'img',
    'p_media_2__id' => 1,
    'p_media_2__name' => 'asdasd',
    'p_media_2__type' => 'img',
);

timethese(100000, {
    pp => sub { my @errs; CGI::Struct::build_cgi_struct(\%inp, \@errs, { dclone => 0 }); },
    xs => sub { my @errs; CGI::Struct::XS::build_cgi_struct(\%inp, \@errs, { dclone => 0 }); },
});
