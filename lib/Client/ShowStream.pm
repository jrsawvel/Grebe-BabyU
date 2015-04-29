package ShowStream;

use strict;
use URI::Escape;
use REST::Client;
use JSON::PP;
use JRS::StrNumUtils;
use Client::RSS;

sub show_articles {
    my $tmp_hash = shift;
    _show_stream($tmp_hash, "articles");
}

sub show_articles_for_author {
    my $tmp_hash = shift;
    _show_stream($tmp_hash, "userarticles");
}

sub show_notes {
    my $tmp_hash = shift;
    _show_stream($tmp_hash, "notes");
}

sub show_drafts {
    my $tmp_hash = shift;
    _show_stream($tmp_hash, "drafts");
}

sub show_changes {
    my $tmp_hash = shift;
    _show_stream($tmp_hash, "changes");
}

sub show_blocks {
    my $tmp_hash = shift;
    _show_stream($tmp_hash, "blocks");
}

sub _show_stream {
    my $tmp_hash = shift;
    my $post_type = shift;

    my $user_name    = User::get_logged_in_username(); 
    my $user_id      = User::get_logged_in_userid(); 
    my $session_id   = User::get_logged_in_sessionid(); 

    my $doing_rss = 0;

    my $query_string; 

    my $template_name = "stream";

    if ( $session_id ) {
        $query_string = "/?user_name=$user_name&user_id=$user_id&session_id=$session_id";
    } else {
        $query_string = "/?";
    }

    my $posts_api_url = Config::get_value_for("api_url") . "/posts";

    my $page_num = 1;
    if ( StrNumUtils::is_numeric($tmp_hash->{one}) ) {
        $page_num = $tmp_hash->{one};
        if ( $page_num > 1 ) {
            $query_string .= "&page=$page_num";
        }
    } elsif ( $tmp_hash->{one} and lc($tmp_hash->{one}) eq "rss" ) {
        $doing_rss =  1;
    }

    # for now, the default display for notes will be the notes for the logged-in user.
    # notes and drafts, however, are not private posts.

    my $author_name;

    if ( $post_type eq "userarticles" ) {
        $query_string .= "&author=$tmp_hash->{one}";
        $author_name = $tmp_hash->{one};
        if ( StrNumUtils::is_numeric($tmp_hash->{two}) ) {
            $page_num = $tmp_hash->{two};
            if ( $page_num > 1 ) {
                $query_string .= "&page=$page_num";
            }
        } elsif ( lc($tmp_hash->{two}) eq "rss" ) {
            $doing_rss =  1;
        }
    } elsif ( $post_type eq "notes" ) {
        $query_string .= "&type=note&author=$user_name";
        $template_name = "notes";
    } elsif ( $post_type eq "drafts" ) {
        $query_string .= "&type=draft&author=$user_name";
        $template_name = "drafts";
    } elsif ( $post_type eq "changes" ) {
        $query_string .= "&sortby=modified";
    } elsif ( $post_type eq "blocks" ) {
        $query_string .= "&sortby=blocks";
        $template_name = "blocks";
    }

    my $rest = REST::Client->new();
    $posts_api_url .= $query_string;

    $rest->GET($posts_api_url);

    my $rc = $rest->responseCode();

    if ( $rc >= 400 and $rc < 500 ) {
        if ( $rc == 401 or $rc == 403 ) {
            my $t = Page->new("notloggedin");
            $t->display_page("Login");
        } else {
            my $json = decode_json $rest->responseContent();
            Page->report_error("user", "$json->{user_message}", $json->{system_message});
        }
    } elsif ( $rc >= 200 and $rc < 300 ) {
        my $json = decode_json $rest->responseContent();
        if ( $doing_rss ) {
             # $searchurlstr = uri_escape($searchurlstr);
             if ( $post_type eq "userarticles" ) {
                 RSS::display_rss($json->{posts}, "Articles by $author_name", "/$post_type/$author_name");
             } else {
                 RSS::display_rss($json->{posts}, ucfirst($post_type), "/$post_type");
             }
        } else {
            _display_stream($json, $page_num, $template_name, undef, $post_type, $author_name);
        }
    } else  {
        Page->report_error("user", "Unable to complete request.", "Invalid response code returned from API.");
    }
}

sub _display_stream {
    my $json           = shift;
    my $page_num       = shift;
    my $template_name  = shift;
    my $search_hash    = shift;
    my $function       = shift;
    my $author_name    = shift;
   
    my $posts          = $json->{posts};
    my $next_link_bool = $json->{next_link_bool};
 
    if ( !defined($template_name) ) {
        $template_name = "stream";
    }

    my $t;

    my $len = @$posts;

    if ( defined($search_hash) ) {
        $t = Page->new($template_name);
        if ( $search_hash->{search_type} eq "string" ) {
            $t->set_template_variable("search_type",   "search");
            $function = "search/$search_hash->{search_string}";
        } else {
            $t->set_template_variable("search_type",   $search_hash->{search_type});
            $function = "tag/$search_hash->{search_string}";
        }
        $t->set_template_variable("search_string", $search_hash->{search_string});
        $t->set_template_variable("keywords",      uri_unescape($search_hash->{search_string}));
        if ( $len < 1 ) {
            $t->set_template_variable("nomatches", 1);
        }
    } else {
        $t = Page->new($template_name);
    }

    if ( $function eq "userarticles" ) {
        $function = "userarticles/$author_name";
    }  

    $t->set_template_loop_data("stream_loop", $posts);

    my $max_items_on_main_page = Config::get_value_for("max_entries_on_page");
 
    if ( $page_num == 1 ) {
        $t->set_template_variable("not_page_one", 0);
    } else {
        $t->set_template_variable("not_page_one", 1);
    }

    if ( $len >= $max_items_on_main_page && $next_link_bool ) {
        $t->set_template_variable("not_last_page", 1);
    } else {
        $t->set_template_variable("not_last_page", 0);
    }

    my $previous_page_num = $page_num - 1;
    my $next_page_num     = $page_num + 1;

    my $next_page_url     = "/$function/$next_page_num";
    my $previous_page_url = "/$function/$previous_page_num";

    $t->set_template_variable("next_page_url", $next_page_url);
    $t->set_template_variable("previous_page_url", $previous_page_url);

    if ( $template_name eq "stream" ) {
        if ( $json->{filter_by_author_name} ) {
            $t->set_template_variable("filter_by_author_name", $json->{filter_by_author_name});
            $t->set_template_variable("filtered_author_name",        $author_name);
            $t->set_template_variable("blog_title",        $author_name);
            if ( defined($json->{blog_description}) ) {
                $t->set_template_variable("blog_description",  $json->{blog_description});
            }
            if ( defined($json->{blog_banner_image}) ) {
                $t->set_template_variable("background_image",  $json->{blog_banner_image});
            } else {
                $t->set_template_variable("background_image",  Config::get_value_for("background_image")); 
            }
            if ( defined($json->{blog_author_image}) ) {
                $t->set_template_variable("blog_author_image",  $json->{blog_author_image});
            }
        } else {
            $t->set_template_variable("background_image",  Config::get_value_for("background_image")); 
            $t->set_template_variable("blog_description",  Config::get_value_for("site_description"));
            $t->set_template_variable("blog_title",        Config::get_value_for("site_name"));
        }
    }

    $t->display_page("Home page");
}

1;
