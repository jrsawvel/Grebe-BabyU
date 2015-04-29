package Stream;

use strict;

use JSON::PP;
use CGI qw(:standard);
use Config::Config;
use JRS::DateTimeFormatter;
use JRS::StrNumUtils;
use API::Utils;
use API::Error;
use API::Db;
use API::GetUser;
use API::Format;

my $pt_db_source       = Config::get_value_for("database_host");
my $pt_db_catalog      = Config::get_value_for("database_name");
my $pt_db_user_id      = Config::get_value_for("database_username");
my $pt_db_password     = Config::get_value_for("database_password");

my $dbtable_posts   = Config::get_value_for("dbtable_posts");
my $dbtable_users      = Config::get_value_for("dbtable_users");

sub get_post_stream {
    my $user_auth    = shift;

#    my %uri_values = _get_uri_values($tmp_hash);
    my %uri_values = _get_query_string_values();

    if ( !StrNumUtils::is_numeric($uri_values{page_num}) ) {
        Error::report_error("400", "Invalid access.", "Page number is not numeric.");
    }

    my $user_ref;
    if ( $uri_values{filter_by_author_name} ) {
        $user_ref = GetUser::_get_user($uri_values{author_name}, "", 0, "yes"); 
        if ( !$user_ref->{user_exists} ) {
            Error::report_error("400", "Nothing found.", "User $uri_values{author_name} does not exist.");
        }
        if ( $user_ref->{desc_markup} =~ m|^blog-description[\s]*=[\s]*(.+)|im ) {
            $user_ref->{blog_description} = $1;
        }
        if ( $user_ref->{desc_markup} =~ m|^blog-author-image[\s]*=[\s]*(.+)|im ) {
            $user_ref->{blog_author_image} = $1;
        }
        if ( $user_ref->{desc_markup} =~ m|^blog-banner-image[\s]*=[\s]*(.+)|im ) {
            $user_ref->{blog_banner_image} = $1;
        }
    }

    my $sql       =  _create_posts_sql(\%uri_values, $user_auth->{logged_in_user_id}, $user_ref);
    my @posts     =  _get_stream($sql);
    @posts        =  _format_posts(\@posts, $user_auth->{logged_in_user_id});
    my $json_str  =  _format_json_posts(\@posts, $user_auth->{logged_in_user_id}, \%uri_values, $user_ref);

    print header('application/json', '200 Accepted');
    print $json_str;
    exit;
}

sub _create_posts_sql {
    my $hash_ref     = shift; 
    my $logged_in_user_id = shift;
    my $user_ref = shift;

    my $max_entries = Config::get_value_for("max_entries_on_page");
    my $page_offset = $max_entries * ($hash_ref->{page_num} - 1);
    my $max_entries_plus_one = $max_entries + 1;

#    my $offset = Utils::get_time_offset();

    my $where_str = " a.parent_id = 0 and a.post_type = '$hash_ref->{post_type}' and ( a.post_status = 'o'  or (a.author_id=$logged_in_user_id and a.post_status='d') ) ";

    if ( $hash_ref->{filter_by_author_name} ) {
        $where_str = " a.author_id=$user_ref->{user_id} and " . $where_str;
    } elsif ( $hash_ref->{sort_by} eq "blocks" ) {
        $where_str = " a.block_id > 0 and " . $where_str;        
    }

    my $limit_str = " limit $max_entries_plus_one offset $page_offset ";

    my $order_by = "a.created_date";
    $order_by    = "a.modified_date" if $hash_ref->{sort_by} eq "modified";
    $order_by    = "a.block_id"      if $hash_ref->{sort_by} eq "blocks";

    my $sql = <<EOSQL;
        select a.post_id, a.title, a.uri_title, a.markup_text, a.formatted_text, a.author_id, a.post_type, a.post_status, a.tags, a.modified_date, u.user_name, a.block_id, 
        date_format(date_add(a.modified_date, interval 0 hour), '%b %d, %Y') as formatted_date
        from $dbtable_posts a, $dbtable_users u 
        where $where_str and a.author_id = u.user_id
        order by $order_by desc
        $limit_str
EOSQL

    return $sql;
}

sub _get_stream {
    my $sql = shift;

    my $db = Db->new($pt_db_catalog, $pt_db_user_id, $pt_db_password);
    Error::report_error("500", "Error connecting to database.", $db->errstr) if $db->err;

    my @loop_data = $db->gethashes($sql);
    Error::report_error("500", "Error executing SQL.", $db->errstr) if $db->err;

    $db->disconnect;
    Error::report_error("500", "Error disconnecting from database.", $db->errstr) if $db->err;

    return @loop_data;
}

sub _format_posts {
    my $loop_data         = shift;
    my $logged_in_user_id = shift;

    my @posts = ();

    foreach my $hash_ref ( @$loop_data ) {

        my $tmp_post = StrNumUtils::remove_html($hash_ref->{formatted_text});
        my @tmp_arr = split(/\s+/s, $tmp_post);
        my $tmp_word_count = @tmp_arr;
        $hash_ref->{readingtime} = 0;
        $hash_ref->{readingtime} = int($tmp_word_count / 180) if $tmp_word_count >= 180;

        $hash_ref->{reader_is_author} = 0;
        if ( $hash_ref->{author_id} == $logged_in_user_id ) {
            $hash_ref->{reader_is_author} = 1;
            if ( $hash_ref->{post_status} eq "o" ) {
                $hash_ref->{user_action} = "delete";
            } elsif ( $hash_ref->{post_status} eq "d" ) {
                $hash_ref->{user_action} = "undelete";
            }
        }
        
        delete($hash_ref->{author_id});
        delete($hash_ref->{post_status});

        if ( $hash_ref->{markup_text} =~ m|^imageheader[\s]*=[\s]*(.+)|im ) {
            $hash_ref->{imageheader} = 1;
            $hash_ref->{imageheaderurl}   = StrNumUtils::trim_spaces($1);
        }

        if ( $hash_ref->{markup_text} =~ m|^largeimageheader[\s]*=[\s]*(.+)|im ) {
            $hash_ref->{imageheader} = 1;
            $hash_ref->{imageheaderurl}   = StrNumUtils::trim_spaces($1);
        }
       
        my $tmp_tag_str = $hash_ref->{tags};
        if ( length($tmp_tag_str) > 2 ) {
            $hash_ref->{tag_link_str} = Format::create_blog_tag_list($tmp_tag_str);
            $hash_ref->{tags_exist}   = 1;
        }
        delete($hash_ref->{tags});

        my $str = $hash_ref->{formatted_text}; 

        if ( $str =~ m|<p><more \/><\/p>(.*?)<p><\/more><\/p>(.*?)$|is ) {
            $str = $1;
            my $tmp_extended = StrNumUtils::trim_spaces($2);
            if ( length($tmp_extended) > 0 ) {
                $hash_ref->{more_text_exists} = 1;
                if ( !Utils::get_power_command_on_off_setting_for("more_text", $hash_ref->{markup_text}, 1) ) {
                    $hash_ref->{more_text_exists} = 0;
                }
            }
        } elsif ( $str =~ m|^(.*?)<p><more \/><\/p>(.*?)$|is ) {
            $str = $1;
            my $tmp_extended = StrNumUtils::trim_spaces($2);
            if ( length($tmp_extended) > 0 ) {
                $hash_ref->{more_text_exists} = 1;
            }
        } elsif ( $hash_ref->{post_type} eq "note" ) {
            $str = StrNumUtils::remove_html($str);
            if ( length($str) > 300 ) {
                $str = substr $str, 0, 300;
                $str .= " ...";
                $hash_ref->{more_text_exists} = 1;
            } else {
                $str = Format::hashtag_to_link($str);
            }
        }
        $hash_ref->{formatted_text} = $str;

        delete($hash_ref->{markup_text});

        if ( $hash_ref->{post_type} eq "note" ) {
            delete($hash_ref->{title});
        }

        push(@posts, $hash_ref);
    }

    return @posts;
}

sub _format_json_posts {
    my $posts = shift;
    my $logged_in_user_id = shift;
    my $hash_ref = shift;
    my $user_ref = shift;

    my $max_entries = Config::get_value_for("max_entries_on_page");
    my $len = @$posts;
    my %hash;
    $hash{next_link_bool} = 0;
    if ( $len > $max_entries ) {
        $hash{next_link_bool} = 1;
        pop @$posts;
    }
    $hash{status}                =  200;
    $hash{description}           = "OK";
    $hash{logged_in_user_id}     = $logged_in_user_id;
    $hash{posts}                 =  $posts;
    $hash{filter_by_author_name} = $hash_ref->{filter_by_author_name};

    if ( $hash_ref->{filter_by_author_name} ) {
        $hash{author_name}           = $hash_ref->{author_name}; 
        $hash{blog_description}      = $user_ref->{blog_description};  
        $hash{blog_author_image}     = $user_ref->{blog_author_image};  
        $hash{blog_banner_image}     = $user_ref->{blog_banner_image}; 
    }

    my $json_str = encode_json \%hash;
    return $json_str;
}

sub _get_uri_values {
    my $hash_ref = shift;

    my %uri_values;
    $uri_values{page_num} = 1;
    $uri_values{filter_by_user_name} = 0;

    if ( exists($hash_ref->{one}) ) {
        if ( $hash_ref->{one} eq "page" ) {
            $uri_values{page_num} = $hash_ref->{two} if exists($hash_ref->{two});
        } elsif ( $hash_ref->{one} eq "user" ) {
            $uri_values{user_name} = $hash_ref->{two} if exists($hash_ref->{two});
            $uri_values{filter_by_user_name} = 1 if exists($hash_ref->{two});
            if ( exists($hash_ref->{three}) ) {
                if ( $hash_ref->{three} eq "page" ) {
                    $uri_values{page_num} = $hash_ref->{four} if exists($hash_ref->{four});
                }
            } 
        }
    }

    return %uri_values;
}

sub _get_query_string_values {

    my $q = new CGI;

    my %uri_values;
    $uri_values{page_num}              = 1;
    $uri_values{filter_by_author_name} = 0;
    $uri_values{post_type}             = "article";
    $uri_values{sort_by}               = "created";

    $uri_values{page_num} = $q->param("page")   if $q->param("page");
    $uri_values{sort_by}  = $q->param("sortby") if $q->param("sortby");

    if ( $q->param("author") ) {
        $uri_values{author_name} = $q->param("author");
        $uri_values{filter_by_author_name} = 1 ;
    }
    
    $uri_values{post_type} = $q->param("type") if $q->param("type");

    return %uri_values;
}

1;

