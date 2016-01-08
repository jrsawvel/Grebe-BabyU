package EditPost;

use strict;
use REST::Client;
use JSON::PP;
use HTML::Entities;
use Encode;

sub show_post_to_edit {
    my $tmp_hash = shift;  

    my $user_name    = User::get_logged_in_username(); 
    my $user_id      = User::get_logged_in_userid(); 
    my $session_id   = User::get_logged_in_sessionid(); 
    my $query_string = "/?user_name=$user_name&user_id=$user_id&session_id=$session_id&text=full";

    my $post = $tmp_hash->{one}; 

    my $api_url = Config::get_value_for("api_url") . "/posts/" . $post;

    my $rest = REST::Client->new();
    $api_url .= $query_string;
    $rest->GET($api_url);

    my $rc = $rest->responseCode();

    my $json = decode_json $rest->responseContent();


    if ( $rc >= 200 and $rc < 300 ) {

        if ( !$json->{reader_is_author} ) {
            Page->report_error("user", "Unable to perform action.", "You are not logged in.");
        }

        my $t = Page->new("editpostform");
        $t->set_template_variable("viewing_old_version",  $json->{parent_id});
        $t->set_template_variable("parent_id",            $json->{parent_id});
        $t->set_template_variable("version_number",       $json->{version});
        $t->set_template_variable("uri_title",            $json->{uri_title});
        $t->set_template_variable("title",                $json->{title}) if $json->{post_type} eq "article";
        $t->set_template_variable("markup_text",          decode_entities($json->{markup_text}, '<>&'));
        $t->set_template_variable("post_id",              $json->{post_id});
        $t->set_template_variable("post_digest",          $json->{post_digest});
        $t->display_page("Editing " . $json->{title});
    } elsif ( $rc >= 400 and $rc < 500 ) {
            Page->report_error("user", "$json->{user_message}", $json->{system_message});
    } else  {
        # Page->report_error("user", "Unable to complete request.", "Invalid response code returned from API.");
        Page->report_error("user", "Unable to complete request. Invalid response code returned from API.", "$json->{user_message} $json->{system_message}");
    }
}

sub splitscreen_edit {
    my $tmp_hash = shift;  

    my $user_name    = User::get_logged_in_username(); 
    my $user_id      = User::get_logged_in_userid(); 
    my $session_id   = User::get_logged_in_sessionid(); 
    my $query_string = "/?user_name=$user_name&user_id=$user_id&session_id=$session_id&text=full";

    my $post = $tmp_hash->{one}; 

    my $api_url = Config::get_value_for("api_url") . "/posts/" . $post;

    my $rest = REST::Client->new();
    $api_url .= $query_string;
    $rest->GET($api_url);

    my $rc = $rest->responseCode();

    my $json = decode_json $rest->responseContent();

    if ( $rc >= 200 and $rc < 300 ) {

        if ( !$json->{reader_is_author} ) {
            Page->report_error("user", "Unable to perform action.", "You are not logged in.");
        }

        my $t = Page->new("splitscreenform");
        $t->set_template_variable("action", "updateblog");
        $t->set_template_variable("api_url", Config::get_value_for("api_url"));
        $t->set_template_variable("markup_text",     decode_entities($json->{markup_text}, '<>&'));
        $t->set_template_variable("post_id",         $json->{post_id});
        $t->set_template_variable("post_digest",     $json->{post_digest});
        $t->display_page_min("Editing - Split Screen " . $json->{title});
    } elsif ( $rc >= 400 and $rc < 500 ) {
            Page->report_error("user", "$json->{user_message}", $json->{system_message});
    } else  {
        Page->report_error("user", "Unable to complete request. Invalid response code returned from API.", "$json->{user_message} $json->{system_message}");
    }
}

sub update_post {
    my $q = new CGI;
    my $err_msg = "";

    my $post_id     = $q->param("post_id");
    my $post_digest = $q->param("post_digest");
    my $post_text   = $q->param("markup_text");

    my $markup_text = Encode::decode_utf8($post_text);
    $markup_text = HTML::Entities::encode($markup_text ,'^\n^\r\x20-\x25\x27-\x7e');

    my $edit_reason = $q->param("edit_reason");
    $edit_reason    = encode_entities($edit_reason, '<>');

    my $submit_type  = $q->param("sb"); # Preview or Update

    my $user_name    = User::get_logged_in_username(); 
    my $user_id      = User::get_logged_in_userid(); 
    my $session_id   = User::get_logged_in_sessionid(); 

    my $headers = {
        'Content-type' => 'application/x-www-form-urlencoded'
    };

    my $rest = REST::Client->new( {
           host => Config::get_value_for("api_url"),
    } );

    my %hash;
    $hash{post_text}   = $markup_text;
    $hash{submit_type} = $submit_type;
    $hash{post_id}     = $post_id;
    $hash{post_digest} = $post_digest;
    $hash{edit_reason} = $edit_reason;
    my $json_str = encode_json \%hash;

    my $pdata = {
        'json'        => $json_str,
        'user_name'   => $user_name,
        'user_id'     => $user_id,
        'session_id'  => $session_id,
    };
    my $params = $rest->buildQuery( $pdata );

    $params =~ s/\?//;

    $rest->PUT( "/posts" , $params , $headers );

    my $rc = $rest->responseCode();

    my $json = decode_json $rest->responseContent();

    if ( $rc >= 200 and $rc < 300 ) {
        if ( $submit_type eq "Update" ) {
            my $url = Config::get_value_for("home_page") . "/" . $json->{post_id} . "/writetemplate";
            print $q->redirect( -url => $url);
            exit;
        } elsif ( $submit_type eq "Preview" ) {
            my $t = Page->new("editpostform");
            $t->set_template_variable("formatted_text",       decode_entities($json->{formatted_text}, '<>&'));
#            $t->set_template_variable("markup_text",          $post_text);
            $t->set_template_variable("markup_text",          $markup_text); # changes to this on 17oct2014 to handle extended ascii
            $t->set_template_variable("viewing_old_version",  $json->{parent_id});
            $t->set_template_variable("version_number",       $json->{version});
            $t->set_template_variable("post_digest",          $json->{post_digest});
            $t->set_template_variable("uri_title",            $json->{uri_title});
            $t->set_template_variable("post_id",              $json->{post_id});
            $t->set_template_variable("edit_reason",          $json->{edit_reason});
            $t->set_template_variable("title",                $json->{title}) if $json->{post_type} eq "article";

            $t->display_page("Editing " . $json->{title});
        }
    } elsif ( $rc >= 400 and $rc < 500 ) {
        my $t = Page->new("errorpage");
        $t->set_template_variable("errmsg", "Error: $json->{description} - $json->{user_message}");
        # $t->set_template_variable("post_text",    $json->{markup_content});
        $t->set_template_variable("post_text",    $post_text);
        $t->display_page("Message error"); 
    } else  {
        # Page->report_error("user", "Unable to complete request.", "Invalid response code returned from API.");
        Page->report_error("user", "Unable to complete request. Invalid response code returned from API.", "$json->{user_message} $json->{system_message}");
    }
}

1;


__END__

    if ( $enhanced ) {
        $t = Page->new("enheditblogpostform");
    } else { 
        $t = Page->new("editblogpostform");
    }

