package TextSize;

use strict;
use warnings;

sub set_text_size {
    my $tmp_hash = shift;  

    my $text_size = $tmp_hash->{one};

    if ( !$text_size ) {
        $text_size = '';
    }
  
    my $q = new CGI;
    my $cookie_prefix = Config::get_value_for("cookie_prefix");
    my $cookie_domain = Config::get_value_for("domain_name");
    my $c1 = $q->cookie( -name => $cookie_prefix . "textsize", -value => "$text_size", -path => "/", -expires => "+10y", -domain => ".$cookie_domain");
    my $url = $ENV{HTTP_REFERER};
    print $q->redirect( -url => $url, -cookie => [$c1] );
}

1;
