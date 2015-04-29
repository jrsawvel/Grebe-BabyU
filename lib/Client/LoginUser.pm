package LoginUser;

use strict;
use warnings;

use REST::Client;
use JSON::PP;

sub show_login_form {
    my $t = Page->new("loginform");
    $t->display_page("Login Form");
}

sub report_invalid_login
{
    if ( Config::get_value_for("passwordless_login") ) {
        show_passwordless_login_form();
    }

    my $t = Page->new("invalidlogin");
    $t->display_page("Invalid Login");
}

sub show_passwordless_login_form {
    if ( Config::get_value_for("passwordless_login") ) {
        my $t = Page->new("passwordlessloginform");
        $t->display_page("Passwordless Login Form");
    } else {
        Page->report_error("user", "Unable to complete request.", "Action does not exist.");
    }
}

sub login {
    my $tmp_hash = shift; # ref to hash

    if ( Config::get_value_for("passwordless_login") ) {
        show_passwordless_login_form();
    }

    my $error_exists = 0;

    my $q = new CGI;
    my $email             = $q->param("email");
    my $password          = $q->param("password");
    my $savepassword      = $q->param("savepassword");
    if ( !defined($savepassword) ) {
        $savepassword = "no";
    } 

    my $headers = {
        'Content-type' => 'application/x-www-form-urlencoded'
    };
    my $rest = REST::Client->new( {
           host => Config::get_value_for("api_url"),
    } );
    my %hash;
    $hash{email}    = $email;
    $hash{password} = $password;
    my $json_str = encode_json \%hash;
    my $pdata = {
        'json' => $json_str,
    };
    my $params = $rest->buildQuery( $pdata );
    $params =~ s/\?//;
    $rest->POST( "/users/login" , $params , $headers );
    my $rc = $rest->responseCode();
    my $json = decode_json $rest->responseContent();

    if ( $rc >= 200 and $rc < 300 ) {
        my $cookie_prefix = Config::get_value_for("cookie_prefix");
        my $cookie_domain = Config::get_value_for("domain_name");
        my ($c1, $c2, $c3, $c4);
        if ( $savepassword eq "yes" ) {
            $c1 = $q->cookie( -name => $cookie_prefix . "userid",          -value => "$json->{user_id}",     -path => "/",  -expires => "+10y",  -domain => ".$cookie_domain");
            $c2 = $q->cookie( -name => $cookie_prefix . "username",        -value => "$json->{user_name}",   -path => "/",  -expires => "+10y",  -domain => ".$cookie_domain");
            $c3 = $q->cookie( -name => $cookie_prefix . "sessionid",       -value => "$json->{session_id}",  -path => "/",  -expires => "+10y",  -domain => ".$cookie_domain");
            $c4 = $q->cookie( -name => $cookie_prefix . "current",         -value => "1",                 -path => "/",  -domain => ".$cookie_domain");
        } else {
            $c1 = $q->cookie( -name => $cookie_prefix . "userid",          -value => "$json->{user_id}",     -path => "/",  -domain => ".$cookie_domain");
            $c2 = $q->cookie( -name => $cookie_prefix . "username",        -value => "$json->{user_name}",   -path => "/",  -domain => ".$cookie_domain");
            $c3 = $q->cookie( -name => $cookie_prefix . "sessionid",       -value => "$json->{session_id}",  -path => "/",  -domain => ".$cookie_domain");
            $c4 = $q->cookie( -name => $cookie_prefix . "current",         -value => "1",                 -path => "/",  -domain => ".$cookie_domain");
        }
        my $url = Config::get_value_for("home_page");
        print $q->redirect( -url => $url, -cookie => [$c1,$c2,$c3,$c4] );
    } elsif ( $rc >= 400 and $rc < 500 ) {
        report_invalid_login();
    } else  {
        Page->report_error("user", "Unable to complete request.", "Invalid response code returned from API.");
    }
}

sub no_password_login {
    my $tmp_hash = shift; # ref to hash

    if ( !Config::get_value_for("passwordless_login") ) {
        show_login_form();
    }

    my $error_exists = 0;

    my $q = new CGI;
    my $user_digest     = $tmp_hash->{one};
    my $password_digest = $tmp_hash->{two};
    my $savepassword    = "no";

    my $headers = {
        'Content-type' => 'application/x-www-form-urlencoded'
    };
    my $rest = REST::Client->new( {
           host => Config::get_value_for("api_url"),
    } );
    my %hash;
    $hash{user_digest}      = $user_digest;
    $hash{password_digest}  = $password_digest;
    my $json_str = encode_json \%hash;
    my $pdata = {
        'json' => $json_str,
    };
    my $params = $rest->buildQuery( $pdata );
    $params =~ s/\?//;
    $rest->POST( "/users/nopwdlogin" , $params , $headers );
    my $rc = $rest->responseCode();
    my $json = decode_json $rest->responseContent();

    if ( $rc >= 200 and $rc < 300 ) {
        my $cookie_prefix = Config::get_value_for("cookie_prefix");
        my $cookie_domain = Config::get_value_for("domain_name");
        my ($c1, $c2, $c3, $c4);
        if ( $savepassword eq "yes" ) {
            $c1 = $q->cookie( -name => $cookie_prefix . "userid",          -value => "$json->{user_id}",     -path => "/",  -expires => "+10y",  -domain => ".$cookie_domain");
            $c2 = $q->cookie( -name => $cookie_prefix . "username",        -value => "$json->{user_name}",   -path => "/",  -expires => "+10y",  -domain => ".$cookie_domain");
            $c3 = $q->cookie( -name => $cookie_prefix . "sessionid",       -value => "$json->{session_id}",  -path => "/",  -expires => "+10y",  -domain => ".$cookie_domain");
            $c4 = $q->cookie( -name => $cookie_prefix . "current",         -value => "1",                 -path => "/",  -domain => ".$cookie_domain");
        } else {
            $c1 = $q->cookie( -name => $cookie_prefix . "userid",          -value => "$json->{user_id}",     -path => "/",  -domain => ".$cookie_domain");
            $c2 = $q->cookie( -name => $cookie_prefix . "username",        -value => "$json->{user_name}",   -path => "/",  -domain => ".$cookie_domain");
            $c3 = $q->cookie( -name => $cookie_prefix . "sessionid",       -value => "$json->{session_id}",  -path => "/",  -domain => ".$cookie_domain");
            $c4 = $q->cookie( -name => $cookie_prefix . "current",         -value => "1",                 -path => "/",  -domain => ".$cookie_domain");
        }
        my $url = Config::get_value_for("home_page");
        print $q->redirect( -url => $url, -cookie => [$c1,$c2,$c3,$c4] );
    } elsif ( $rc >= 400 and $rc < 500 ) {
        report_invalid_login();
    } else  {
        Page->report_error("user", "Unable to complete request.", "Invalid response code returned from API.");
    }
}

1;
