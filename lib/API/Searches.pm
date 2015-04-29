package Searches;

use strict;

use CGI qw(:standard);
use CGI::Carp qw(fatalsToBrowser);
use API::Stream;
use API::Auth;
use API::Error;
use API::SearchPosts;

sub searches {
    my $tmp_hash = shift;

    my $q = new CGI;

    my $request_method = $q->request_method();

    my $user_auth;
    $user_auth->{user_name}    = $q->param("user_name");
    $user_auth->{user_id}      = $q->param("user_id");
    $user_auth->{session_id}   = $q->param("session_id");
    $user_auth->{logged_in_user_id} = 0;

    my $hash = Auth::authenticate_user($user_auth);
    if ( $hash->{status} == 200 ) {
        $user_auth->{logged_in_user_id} = $user_auth->{user_id};
    }

    if ( $request_method eq "GET" ) {
        if ( $tmp_hash->{one} eq "tag" ) {
            SearchPosts::do_tag_search($user_auth, $tmp_hash);
        } elsif ( $tmp_hash->{one} eq "string" ) {
            SearchPosts::do_string_search($user_auth, $tmp_hash);
        }
    } 
    Error::report_error("400", "Not found", "Invalid request");  
}

1;
