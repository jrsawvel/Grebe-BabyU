package NewPost;

use strict;

use REST::Client;
use JSON::PP;
use HTML::Entities;
use Encode;
use Client::ShowStream;

sub create_post {
    my $q = new CGI;
    my $post_text   = $q->param("markup_content");

    my $markup_content = Encode::decode_utf8($post_text);
    $markup_content = HTML::Entities::encode($markup_content,'^\n^\r\x20-\x25\x27-\x7e');

    my $submit_type = $q->param("sb"); # Preview or Post 

    my $post_location = $q->param("post_location"); # notes_stream or ?

    my $user_name    = User::get_logged_in_username(); 
    my $user_id      = User::get_logged_in_userid(); 
    my $session_id   = User::get_logged_in_sessionid(); 

    my $headers = {
        'Content-type' => 'application/x-www-form-urlencoded'
    };

    # set up a REST session
    my $rest = REST::Client->new( {
           host => Config::get_value_for("api_url"),
    } );

    my %hash;
    $hash{post_text} = $markup_content;
    $hash{submit_type} = $submit_type;
    my $json_str = encode_json \%hash;

    # then we have to url encode the params that we want in the body
    my $pdata = {
        'json'        => $json_str,
        'user_name'   => $user_name,
        'user_id'     => $user_id,
        'session_id'  => $session_id,
    };
    my $params = $rest->buildQuery( $pdata );

    # but buildQuery() prepends a '?' so we strip that out
    $params =~ s/\?//;

    # then sent the request:
    # POST requests have 3 args: URL, BODY, HEADERS
    $rest->POST( "/posts" , $params , $headers );

    my $rc = $rest->responseCode();

    my $json = decode_json $rest->responseContent();

    if ( $rc >= 200 and $rc < 300 ) {
        if ( $submit_type eq "Post" ) {
            my $url;
            if ( $post_location eq "notes_stream" ) {
                $url = Config::get_value_for("home_page") . "/notes"; 
                # begin change 7Oct2014
                my $notes_json_stream = decode_json $json->{notes_homepage};
                ShowStream::_display_stream($notes_json_stream, 1, "notes", undef, "notes", $user_name);
                # end change 7Oct2014
            } else {
                $url = Config::get_value_for("home_page") . "/" . $json->{post_id} . "/writetemplate";
            }
            print $q->redirect( -url => $url);
            exit;
        } elsif ( $submit_type eq "Preview" ) {
            my $t = Page->new("newpostform");
            $t->set_template_variable("previewingpost", 1);
            $t->set_template_variable("formatted_text", $json->{formatted_text});
            $t->set_template_variable("post_text", $post_text);   

            if ( $json->{post_type} eq "article" ) {
                $t->set_template_variable("is_article", 1);
                $t->set_template_variable("preview_title", $json->{title});
            } 

            $t->display_page("Previewing new post");
        }
    } elsif ( $rc >= 400 and $rc < 500 ) {
        my $t = Page->new("errorpage");
        $t->set_template_variable("errmsg", "Error: $json->{description} - $json->{user_message}");
#        $t->set_template_variable("post_text",    $json->{markup_content});
        $t->set_template_variable("post_text",    $post_text);
        $t->display_page("Message error"); 
    } else  {
        # Page->report_error("user", "Unable to complete request.", "Invalid response code returned from API.");
        Page->report_error("user", "Unable to complete request. Invalid response code returned from API.", "$json->{user_message} $json->{system_message}");
    }
}

1;

