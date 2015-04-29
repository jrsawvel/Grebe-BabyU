package FontType;

use strict;
use warnings;

sub set_font_type {
    my $tmp_hash = shift;  

    my $font_type = $tmp_hash->{one};

    if ( !$font_type ) {
        $font_type = '';
    }
  
    my $q = new CGI;
    my $cookie_prefix = Config::get_value_for("cookie_prefix");
    my $cookie_domain = Config::get_value_for("domain_name");
    my $c1 = $q->cookie( -name => $cookie_prefix . "fonttype", -value => "$font_type", -path => "/", -expires => "+10y", -domain => ".$cookie_domain");
    my $url = $ENV{HTTP_REFERER};
    print $q->redirect( -url => $url, -cookie => [$c1] );
}

1;
