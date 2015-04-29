package Search;

use strict;
use REST::Client;
use JSON::PP;
use URI::Escape;
use Client::ShowStream;
use Client::RSS;

sub display_search_form {
    my $t = Page->new("searchform");
    $t->display_page("Search form");
}

sub string_search {
    my $tmp_hash = shift;  

    my %hash;
    $hash{search_string} = $tmp_hash->{one};
    $hash{search_type}   = "string";
    $hash{page_num}      = 1; 
    $hash{doing_rss}     = 0;
    $hash{sortby_userid} = 0;

    if ( lc($tmp_hash->{two}) eq "rss" ) {
        $hash{doing_rss} =  1;
    } elsif ( StrNumUtils::is_numeric($tmp_hash->{two}) ) {
        $hash{page_num} = $tmp_hash->{two};
    }

    if ( !defined($hash{search_string}) ) {
        my $q = new CGI;
        my $search_string = $q->param("keywords");

        if ( !defined($search_string) ) {
            Page->report_error("user", "Missing data.", "Enter keyword(s) to search on.");
        }
        
        $search_string = StrNumUtils::trim_spaces($search_string);
        if ( length($search_string) < 1 ) {
            Page->report_error("user", "Missing data.", "Enter keyword(s) to search on.");
        }
        
        $hash{search_string} = $search_string;
        $hash{search_string} =~ s/ /\+/g;
        $hash{search_string} = uri_escape($hash{search_string});
    }


    my $user_name    = User::get_logged_in_username(); 
    my $user_id      = User::get_logged_in_userid(); 
    my $session_id   = User::get_logged_in_sessionid(); 
    my $query_string = "/?user_name=$user_name&user_id=$user_id&session_id=$session_id";

    my $api_url = Config::get_value_for("api_url") . "/searches/$hash{search_type}/$hash{search_string}/$hash{page_num}"; 

    my $rest = REST::Client->new();
    $api_url .= $query_string;

    $rest->GET($api_url);

    my $rc = $rest->responseCode();
    my $json = decode_json $rest->responseContent();
    if ( $rc >= 200 and $rc < 300 ) {
        if ( $hash{doing_rss} ) {
             my $searchurlstr = $hash{search_string};
             $searchurlstr    =~ s/ /\+/g;
             $searchurlstr = uri_escape($searchurlstr);
             RSS::display_rss($json->{posts}, "Search results for $hash{search_string}", "/$hash{search_type}/$searchurlstr");
        } else {
            # ShowStream::_display_stream($json->{posts}, $hash{page_num}, $json->{next_link_bool}, "search", \%hash);
            ShowStream::_display_stream($json, $hash{page_num},  "search", \%hash);
        }
    } elsif ( $rc >= 400 and $rc < 500 ) {
            Page->report_error("user", "$json->{user_message}", $json->{system_message});
    } else  {
        Page->report_error("user", "Unable to complete request.", "Invalid response code returned from API.");
    }
}

sub tag_search {
    my $tmp_hash = shift;  

    my %hash;
    $hash{search_string} = $tmp_hash->{one}; # tag name or multiple tag names with OR or AND
    $hash{search_type}   = "tag";
    $hash{page_num}      = 1; 
    $hash{doing_rss}     = 0;
    $hash{sortby_userid} = 0;

    if ( lc($tmp_hash->{two}) eq "rss" ) {
        $hash{doing_rss} =  1;
    } elsif ( StrNumUtils::is_numeric($tmp_hash->{two}) ) {
        $hash{page_num} = $tmp_hash->{two};
    } 

    my $user_name    = User::get_logged_in_username(); 
    my $user_id      = User::get_logged_in_userid(); 
    my $session_id   = User::get_logged_in_sessionid(); 
    my $query_string = "/?user_name=$user_name&user_id=$user_id&session_id=$session_id";

    my $api_url = Config::get_value_for("api_url") . "/searches/$hash{search_type}/$hash{search_string}/$hash{page_num}"; 

    my $rest = REST::Client->new();
    $api_url .= $query_string;
    $rest->GET($api_url);

    my $rc = $rest->responseCode();
    my $json = decode_json $rest->responseContent();
    if ( $rc >= 200 and $rc < 300 ) {
        if ( $hash{doing_rss} ) {
             my $searchurlstr = $hash{search_string};
             $searchurlstr    =~ s/ /\+/g;
             $searchurlstr = uri_escape($searchurlstr);
             RSS::display_rss($json->{posts}, "Search results for tag $hash{search_string}", "/$hash{search_type}/$searchurlstr");
        } else {
            # ShowStream::_display_stream($json->{posts}, $hash{page_num}, $json->{next_link_bool}, "search", \%hash);
            ShowStream::_display_stream($json, $hash{page_num},  "search", \%hash);
        }
    } elsif ( $rc >= 400 and $rc < 500 ) {
            Page->report_error("user", "$json->{user_message}", $json->{system_message});
    } else  {
        Page->report_error("user", "Unable to complete request.", "Invalid response code returned from API.");
    }
}

1;
