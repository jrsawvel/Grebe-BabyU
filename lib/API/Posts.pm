package Posts;

use strict;

use CGI qw(:standard);
use CGI::Carp qw(fatalsToBrowser);
use API::GetPost;
use API::Stream;
use API::CreatePost;
use API::UpdatePost;
use API::PostStatus;
use API::Auth;
use API::Error;
use JRS::StrNumUtils;


sub posts {
    my $tmp_hash = shift;

    my $q = new CGI;

    my $request_method = $q->request_method();

    my $user_auth;
    $user_auth->{user_name}    = $q->param("user_name");
    $user_auth->{user_id}      = $q->param("user_id");
    $user_auth->{session_id}   = $q->param("session_id");
    $user_auth->{logged_in_user_id} = 0;

    my $page_num   = $q->param("page");

    my $hash = Auth::authenticate_user($user_auth);
    if ( $hash->{status} == 200 ) {
        $user_auth->{logged_in_user_id} = $user_auth->{user_id};
    }


    if ( $request_method eq "GET" and StrNumUtils::is_numeric($tmp_hash->{one}) ) {
        my $post_id = $tmp_hash->{one};

        if ( $q->param("action") eq "delete"  or  $q->param("action") eq "undelete" ) {
            if ( $hash->{status} != 200 ) {
                Error::report_error($hash->{status}, $hash->{user_message}, $hash->{system_message});
            } else {
                                                     # delete or undelete  ,  post id,  logged in user id
                PostStatus::change_post_status($q->param("action"), $post_id, $user_auth->{user_id});
            }
        } elsif ( $q->param("related") eq "yes" ) {
            GetPost::get_related_posts_titles($post_id);
        } else {
            GetPost::get_post($user_auth, $post_id);
        }
    } elsif ( $request_method eq "GET" and $tmp_hash->{one} ) {
            GetPost::get_post($user_auth, $tmp_hash->{one});
    } elsif ( $request_method eq "GET" ) {
        Stream::get_post_stream($user_auth);

    } elsif ( $request_method eq "POST" ) {
        if ( $hash->{status} != 200 ) {
            Error::report_error($hash->{status}, $hash->{user_message}, $hash->{system_message});
        } else {
            CreatePost::create_post($tmp_hash, $user_auth->{user_name}, $user_auth->{user_id});
        }

    } elsif ( $request_method eq "PUT" ) {
        if ( $hash->{status} != 200 ) {
            Error::report_error($hash->{status}, $hash->{user_message}, $hash->{system_message});
        } else {
            UpdatePost::update_post($q->param("json"),  $user_auth->{user_name}, $user_auth->{user_id});
        }
    }

}

1;
