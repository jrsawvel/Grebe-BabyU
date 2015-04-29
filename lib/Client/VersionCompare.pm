package VersionCompare;

use strict;
use REST::Client;
use JSON::PP;

sub compare_versions {

    my $user_name    = User::get_logged_in_username(); 
    my $user_id      = User::get_logged_in_userid(); 
    my $session_id   = User::get_logged_in_sessionid(); 
    my $query_string = "/?user_name=$user_name&user_id=$user_id&session_id=$session_id";

    my $q = new CGI;

    my $leftid  = $q->param("leftid");
    my $rightid = $q->param("rightid");

    my $api_url = Config::get_value_for("api_url") . "/versions/" . $leftid . "/" . $rightid;

    my $rest = REST::Client->new();
    $api_url .= $query_string;
    $rest->GET($api_url);

    my $rc = $rest->responseCode();

    my $json = decode_json $rest->responseContent();

    if ( $rc >= 200 and $rc < 300 ) {
        my $t = Page->new("compare");
        $t->set_template_variable("cgi_app",                 "");

        my $top_version = $json->{top_version};

        $t->set_template_variable("title", $top_version->{title});
        $t->set_template_variable("post_id", $top_version->{post_id});
        $t->set_template_variable("uri_title", $top_version->{uri_title});
        
        my $version_data = $json->{version_data};

        $t->set_template_variable("left_version", $version_data->{left_version});
        $t->set_template_variable("left_post_id", $version_data->{left_post_id});
        $t->set_template_variable("left_uri_title", $version_data->{left_uri_title});
        $t->set_template_variable("left_date", $version_data->{left_date});
        $t->set_template_variable("left_time", $version_data->{left_time});
         
        $t->set_template_variable("right_version", $version_data->{right_version});
        $t->set_template_variable("right_post_id", $version_data->{right_post_id});
        $t->set_template_variable("right_uri_title", $version_data->{right_uri_title});
        $t->set_template_variable("right_date", $version_data->{right_date});
        $t->set_template_variable("right_time", $version_data->{right_time});

        $t->set_template_loop_data("compare_loop", $json->{compare_results});

        $t->display_page("Comparing Versions for ???");

    } elsif ( $rc >= 400 and $rc < 500 ) {
            Page->report_error("user", "$json->{user_message}", $json->{system_message});
    } else  {
        Page->report_error("user", "Unable to complete request.", "Invalid response code returned from API.");
    }
}

1;
