package Related;

use strict;
use REST::Client;
use JSON::PP;

sub show_related_posts {
    my $tmp_hash = shift;  

    my $user_name    = User::get_logged_in_username(); 
    my $user_id      = User::get_logged_in_userid(); 
    my $session_id   = User::get_logged_in_sessionid(); 
    my $query_string = "/?user_name=$user_name&user_id=$user_id&session_id=$session_id&related=yes";

    my $post = $tmp_hash->{one}; 

    my $api_url = Config::get_value_for("api_url") . "/posts/" . $post;

    my $rest = REST::Client->new();
    $api_url .= $query_string;
    $rest->GET($api_url);

    my $rc = $rest->responseCode();

    my $json = decode_json $rest->responseContent();

    if ( $rc >= 200 and $rc < 300 ) {
        my $t = Page->new("relatedposts");
        $t->set_template_loop_data("related_posts_loop", $json->{related_posts_titles});
        $t->set_template_variable("cgi_app",                 "");
        $t->set_template_variable("post_id",              $json->{post_id});
        $t->set_template_variable("title",                   $json->{title});
        $t->set_template_variable("uri_title",               $json->{uri_title});
        $t->display_page("Related Posts for $json->{title}");
    } elsif ( $rc >= 400 and $rc < 500 ) {
            Page->report_error("user", "$json->{user_message}", $json->{system_message});
    } else  {
        Page->report_error("user", "Unable to complete request.", "Invalid response code returned from API.");
    }
}

1;
