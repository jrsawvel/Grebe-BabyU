package ChangeStatus;

use strict;
use warnings;

use REST::Client;
use JSON::PP;

sub delete_post {
    my $tmp_hash = shift; # ref to hash
    my $post_id = $tmp_hash->{one};
    _change_post_status("delete", $post_id);
}

sub undelete_post {
    my $tmp_hash = shift; # ref to hash
    my $post_id = $tmp_hash->{one};
    _change_post_status("undelete", $post_id);
}

sub _change_post_status {
    my $action  = shift;
    my $post_id = shift;

    my $user_name    = User::get_logged_in_username(); 
    my $user_id      = User::get_logged_in_userid(); 
    my $session_id   = User::get_logged_in_sessionid(); 
    my $query_string = "/?user_name=$user_name&user_id=$user_id&session_id=$session_id&text=html";

    my $api_url = Config::get_value_for("api_url") . "/posts/" . $post_id;
    my $rest = REST::Client->new();
    $api_url .= $query_string . "&action=$action";
    $rest->GET($api_url);
 
    my $rc = $rest->responseCode();
    my $json = decode_json $rest->responseContent();

    if ( $rc >= 200 and $rc < 300 ) {
        my $url = Config::get_value_for("home_page");
        my $q = new CGI;
        # print $q->redirect( -url => $url);
        print $q->redirect( -url => $ENV{HTTP_REFERER});
        exit;
    } elsif ( $rc >= 400 and $rc < 500 ) {
        if ( $rc == 401 ) {
            my $t = Page->new("notloggedin");
            $t->display_page("Login");
        } else {
            Page->report_error("user", "$json->{user_message}", $json->{system_message});
        }
    } else  {
        Page->report_error("user", "Unable to complete request.", "Invalid response code returned from API.");
    }
}

1;
