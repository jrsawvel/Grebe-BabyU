package TagList;

use strict;
use REST::Client;
use JSON::PP;

sub show_tags {
    my $tmp_hash = shift;  

    my $sort_by = "name";
    $sort_by = $tmp_hash->{one} if $tmp_hash->{one};

    my $user_name    = User::get_logged_in_username(); 
    my $user_id      = User::get_logged_in_userid(); 
    my $session_id   = User::get_logged_in_sessionid(); 
    my $query_string = "/?user_name=$user_name&user_id=$user_id&session_id=$session_id&sortby=$sort_by";

    my $api_url = Config::get_value_for("api_url") . "/tags"; 

    my $rest = REST::Client->new();
    $api_url .= $query_string;
    $rest->GET($api_url);

    my $rc = $rest->responseCode();

    my $json = decode_json $rest->responseContent();

    if ( $rc >= 200 and $rc < 300 ) {
        my $t = Page->new("tags");
        $t->set_template_variable("cgi_app",                 "");

        my $tag_list = $json->{tag_list};
        $t->set_template_loop_data("tags_loop", $tag_list) if @$tag_list > 1; 

        $t->display_page("Tags");
    } elsif ( $rc >= 400 and $rc < 500 ) {
            Page->report_error("user", "$json->{user_message}", $json->{system_message});
    } else  {
        Page->report_error("user", "Unable to complete request.", "Invalid response code returned from API.");
    }
}

1;
