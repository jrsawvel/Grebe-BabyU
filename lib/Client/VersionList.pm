package VersionList;

use strict;
use REST::Client;
use JSON::PP;

sub show_versions {
    my $tmp_hash = shift;  

    my $user_name    = User::get_logged_in_username(); 
    my $user_id      = User::get_logged_in_userid(); 
    my $session_id   = User::get_logged_in_sessionid(); 
    my $query_string = "/?user_name=$user_name&user_id=$user_id&session_id=$session_id";

    my $post = $tmp_hash->{one}; 

    my $api_url = Config::get_value_for("api_url") . "/versions/" . $post;

    my $rest = REST::Client->new();
    $api_url .= $query_string;
    $rest->GET($api_url);

    my $rc = $rest->responseCode();

    my $json = decode_json $rest->responseContent();

    if ( $rc >= 200 and $rc < 300 ) {
        my $t = Page->new("versions");

        my $array_ref = $json->{version_list};
        if ( @$array_ref > 0 ) { 
            $array_ref->[0]->{checked} = "checked=\"checked\"";
            $t->set_template_loop_data("versions_loop",    $array_ref)  if @$array_ref > 0; 
        }

        $t->set_template_variable("cgi_app",                 "");
        $t->set_template_variable("current_post_id",              $json->{post_id});
        $t->set_template_variable("current_title",                   $json->{title});
        $t->set_template_variable("current_uri_title",               $json->{uri_title});
        $t->set_template_variable("current_version",                 $json->{version});
        $t->set_template_variable("current_author_name",             $json->{author_name});
        $t->set_template_variable("current_modified_date",           $json->{formatted_modified_date});
        $t->set_template_variable("current_modified_time",           $json->{formatted_modified_time});
        $t->set_template_variable("current_edit_reason",             $json->{edit_reason});
        $t->display_page("Versions for $json->{title}");
    } elsif ( $rc >= 400 and $rc < 500 ) {
            Page->report_error("user", "$json->{user_message}", $json->{system_message});
    } else  {
        Page->report_error("user", "Unable to complete request.", "Invalid response code returned from API.");
    }
}

1;
