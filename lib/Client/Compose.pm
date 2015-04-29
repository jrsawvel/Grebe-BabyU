package Compose;

use strict;

use REST::Client;
use JSON::PP;

sub show_new_post_form {
    my $user_name    = User::get_logged_in_username(); 
    my $user_id      = User::get_logged_in_userid(); 
    my $session_id   = User::get_logged_in_sessionid(); 
    my $query_string = "/?user_name=$user_name&user_id=$user_id&session_id=$session_id";
    my $api_url      = Config::get_value_for("api_url") . '/users/' . $user_name;
    my $rest = REST::Client->new();
    $api_url .= $query_string;
    $rest->GET($api_url); 
    my $rc = $rest->responseCode();
    my $json = decode_json $rest->responseContent();
    if ( $rc >= 200 and $rc < 300 ) {
        my $t = Page->new("newpostform");
        $t->display_page("Compose new message");
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

sub show_splitscreen_form {
    my $user_name    = User::get_logged_in_username(); 
    my $user_id      = User::get_logged_in_userid(); 
    my $session_id   = User::get_logged_in_sessionid(); 
    my $query_string = "/?user_name=$user_name&user_id=$user_id&session_id=$session_id";
    my $api_url      = Config::get_value_for("api_url") . '/users/' . $user_name;
    my $rest = REST::Client->new();
    $api_url .= $query_string;
    $rest->GET($api_url); 
    my $rc = $rest->responseCode();
    my $json = decode_json $rest->responseContent();
    if ( $rc >= 200 and $rc < 300 ) {
        my $t = Page->new("splitscreenform");
        $t->set_template_variable("action", "addarticle");
        $t->set_template_variable("api_url", Config::get_value_for("api_url"));
        $t->set_template_variable("post_id", 0);
        $t->set_template_variable("post_digest", "undef");
        $t->display_page_min("Creating Post - Split Screen");
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

