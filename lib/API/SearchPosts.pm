package SearchPosts;

use strict;
use warnings;

use JSON::PP;
use CGI qw(:standard);
use URI::Escape;
use JRS::StrNumUtils;
use Config::Config;
use API::Stream;
use API::Error;
use API::Db;

my $pt_db_source       = Config::get_value_for("database_host");
my $pt_db_catalog      = Config::get_value_for("database_name");
my $pt_db_user_id      = Config::get_value_for("database_username");
my $pt_db_password     = Config::get_value_for("database_password");

my $dbtable_posts      = Config::get_value_for("dbtable_posts");
my $dbtable_tags       = Config::get_value_for("dbtable_tags");
my $dbtable_users      = Config::get_value_for("dbtable_users");

sub do_tag_search {
    my $user_auth = shift;
    my $tmp_hash = shift;  
    my %hash;
    $hash{search_text} = $tmp_hash->{two}; # tag name or multiple tag names with OR or AND

    $hash{search_type}   = "tag";
    $hash{page_num}      = 1; 
    $hash{doing_rss}     = 0;
    $hash{sortby_userid} = 0;

    if ( StrNumUtils::is_numeric($tmp_hash->{three}) ) {
        $hash{page_num} = $tmp_hash->{three};
    } 
    
    _search($user_auth, \%hash);
}

sub do_string_search {
    my $user_auth = shift;
    my $tmp_hash = shift;  

    my %hash;
    $hash{search_text} = $tmp_hash->{two};
    $hash{search_type}   = "search";
    $hash{page_num}      = 1; 
    $hash{doing_rss}     = 0;

    if ( StrNumUtils::is_numeric($tmp_hash->{three}) ) {
        $hash{page_num} = $tmp_hash->{three};
    }

    _search($user_auth, \%hash);
}

sub _search {
    my $user_auth = shift;
    my $tmp_hash = shift;  

    my $search_text = $tmp_hash->{search_text}; 
    my $search_type = $tmp_hash->{search_type};
    my $page_num    = $tmp_hash->{page_num};

    my @loop_data = ();
    my $type = "";
    my @search_terms = ();

    # if search term not in query string, get it from the post request in search form.
    if ( !defined($search_text) ) {
        Error::report_error("400", "Missing data.", "Enter keyword(s) to search on.");
    }

    $search_text = uri_unescape($search_text);

    # if the more friendly + signs are used for spaces in query string instead of %20, deal with it here.
    $search_text =~ s/\+/ /g;
        
    if ( ($search_text =~ m/[\s]+AND[\s]+/) and  $search_text =~ m/[\s]+OR[\s]+/ ) {
        Error::report_error("400", "Invalid search query: $search_text.", "Unable to process a mix of AND and OR.");
    }

    if ( $search_text =~ m/[\s]+AND[\s]+/ ) {
# 14mar2013       my @words = split(/[\s]+/, $search_string);
        my @words = split(/AND/, $search_text);
        foreach (@words) {
            push(@search_terms, StrNumUtils::trim_spaces($_)) if ( $_ ne "AND" );
        }
        $type = "all";
    } 
    elsif ( $search_text =~ m/[\s]+OR[\s]+/ ) {
#        my @words = split(/[\s]+/, $search_string);
        my @words = split(/OR/, $search_text);
        foreach (@words) {
            push(@search_terms, StrNumUtils::trim_spaces($_)) if ( $_ ne "OR" );
        }
        $type = "any";
    }    
    else {
        $type = "phrase";
        push(@search_terms, $search_text);
    }

    my $tag_str = "";
    if ( $search_type eq "tag" ) {
        my @st = ();
        foreach (@search_terms) {
# 9may2013            push(@st, "#" . Utils::trim_spaces($_));
            push(@st, "|" . StrNumUtils::trim_spaces($_) . "|");
        }
        @search_terms = @st;
        $tag_str = "Tag:";
    }

    my $searchurlstr = $search_text;
    $searchurlstr    =~ s/ /\+/g;
    $searchurlstr = uri_escape($searchurlstr);

    my $sql       =  _create_sql($type, \@search_terms, $page_num, $search_type, $user_auth->{logged_in_user_id});
    my @posts  =  Stream::_get_stream($sql);
    @posts     =  Stream::_format_posts(\@posts, $user_auth->{logged_in_user_id});
    my %uri_values;
    $uri_values{filter_by_user_name} = 0;
    my $json_str  =  Stream::_format_json_posts(\@posts, $user_auth->{logged_in_user_id}, \%uri_values);

    print header('application/json', '200 Accepted');
    print $json_str;
    exit;

    # prob a task for client code
    # $values{searchstring} = $tag_str . $search_text;
    # $values{searchurlstr} = $searchurlstr;
    # $values{searchurlstr} = $searchurlstr . "/$tmp_hash->{sortby_username}" if $tmp_hash->{sortby_userid};

}

sub _create_sql {
    my $type = shift; 
    my $search_terms = shift;
    my $page_num = shift;
    my $search_type = shift;
    my $logged_in_user_id = shift;

    my $sql = <<EOSQL;
        select a.post_id, a.title, a.uri_title, a.formatted_text, a.author_id, u.user_name, a.post_type, a.post_status, a.tags, a.modified_date, 
        date_format(date_add(a.modified_date, interval 0 hour), '%b %d, %Y') as formatted_date
        from $dbtable_posts a, $dbtable_users u 
EOSQL

    my $max_entries = Config::get_value_for("max_entries_on_page");
    my $page_offset = $max_entries * ($page_num - 1);
    my $max_entries_plus_one = $max_entries + 1;
    my $limit_str = " limit $max_entries_plus_one offset $page_offset ";

    my $search_column = "a.markup_text";
    $search_column = "a.tags" if $search_type eq "tag";

    my @loop_data;

    my $authorid_str = "a.author_id>0";

#    $sql .= " where ($authorid_str and a.parent_id>=0 and a.post_type in ('article','draft','note') and a.post_status='o'  and a.author_id=u.user_id) and ";
    $sql .= " where ($authorid_str and a.parent_id>=0 and a.post_type in ('article','draft','note') and ( a.post_status='o' or (a.author_id=$logged_in_user_id and a.post_status='d') ) and a.author_id=u.user_id) and ";

    if ( $type eq "phrase" ) {
        my $keyword = pop @$search_terms;
        $keyword =~ s/'/''/g;
        $sql .=  " $search_column like '%$keyword%' ";
    }
    elsif ( $type eq "all" ) {
        my $tmp = "";
        foreach my $keyword (@$search_terms) {
            $keyword =~ s/'/''/g;
             $tmp .=  " $search_column like '%$keyword%' AND ";
        }
        # remove the final 'AND '
        $tmp = substr($tmp, 0, length($tmp) - 4);
        $sql .= $tmp;
    }
    elsif ( $type eq "any" ) {
        my $tmp = "";
        foreach my $keyword (@$search_terms) {
            $keyword =~ s/'/''/g;
             $tmp .=  " $search_column like '%$keyword%' OR ";
        }
        # remove the final 'OR '
        $tmp = substr($tmp, 0, length($tmp) - 3);
        # wrap the OR statements with parens to preserve the AND conditions for the entire sql in the WHERE clause.
        $sql .= "($tmp)";
    }

    $sql .= " order by a.modified_date desc $limit_str ";

    return $sql;
}

1;
