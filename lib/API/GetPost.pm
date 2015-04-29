package GetPost;

use strict;

use JSON::PP;
use CGI qw(:standard);
use Config::Config;
use JRS::StrNumUtils;
use API::Error;
use API::Db;
use API::RelatedPosts;

my $pt_db_source       = Config::get_value_for("database_host");
my $pt_db_catalog      = Config::get_value_for("database_name");
my $pt_db_user_id      = Config::get_value_for("database_username");
my $pt_db_password     = Config::get_value_for("database_password");

my $dbtable_posts   = Config::get_value_for("dbtable_posts");
my $dbtable_users      = Config::get_value_for("dbtable_users");

sub get_post {
    my $user_auth   = shift;
    my $post_id     = shift;
    my $subroutine_access_type = shift; # if "private," then another API module is accessing this subroutine.

    my $q = new CGI;

    my $post_return_data = "full"; # markup = return only the markup text. html = return only html. full = return all database data for the post.
    $post_return_data = $q->param("text") if $q->param("text");

# if want to access post by URI title only, then comment out this check.
#    if ( !StrNumUtils::is_numeric($post_id) ) {
#        Error::report_error("400", "Invalid post ID.", "ID is not numeric.");
#    }

    if ( !defined($post_id) || length($post_id) < 1 )  { 
        Error::report_error("400", "Invalid post ID.", "ID is missing.");
    }

    my $hash_ref = _get_post($post_id);

    if ( !$hash_ref ) {
        if ( $subroutine_access_type ne "private" ) {
            Error::report_error("404", "Post unavailable.", "Post ID not found");
        } else {
            return $hash_ref;
        }
    } else {
        $hash_ref->{status}            = 200;
        $hash_ref->{description}       = "OK";
        $hash_ref->{table_of_contents} = 0;

        if ( Utils::get_power_command_on_off_setting_for("toc", $hash_ref->{markup_text}, 0) ) {
             $hash_ref->{table_of_contents} = 1;
        }

        if ( $hash_ref->{markup_text} =~ m|^imageheader[\s]*=[\s]*(.+)|im ) {
            $hash_ref->{usingimageheader} = 1;
            $hash_ref->{imageheaderurl}   = StrNumUtils::trim_spaces($1);
        }

        if ( $hash_ref->{markup_text} =~ m|^largeimageheader[\s]*=[\s]*(.+)|im ) {
            $hash_ref->{usinglargeimageheader} = 1;
            $hash_ref->{largeimageheaderurl}   = StrNumUtils::trim_spaces($1);
        }

        if ( $hash_ref->{author_id} != $user_auth->{logged_in_user_id} ) {
            # delete($hash_ref->{post_id});
            delete($hash_ref->{author_id});
            delete($hash_ref->{post_digest});
            if ( $post_return_data eq "full" ) {
                delete($hash_ref->{markup_text});
            }
            $hash_ref->{reader_is_author} = 0;
        } else {
            $hash_ref->{reader_is_author} = 1;
        }

        if ( $post_return_data eq "html" ) {
            delete($hash_ref->{markup_text});
        }
   
        my @related_posts = RelatedPosts::get_related_posts($hash_ref->{post_id}, $hash_ref->{tags});
        $hash_ref->{related_posts_count} = @related_posts;

        my $tmp_post = StrNumUtils::remove_html($hash_ref->{formatted_text});
        $hash_ref->{word_count} = scalar(split(/\s+/s, $tmp_post));
        $hash_ref->{reading_time} = 0;
        $hash_ref->{reading_time} = int($hash_ref->{word_count} / 180) if $hash_ref->{word_count} >= 180;

        if ( $subroutine_access_type ne "private" ) {
            my $json_str = encode_json $hash_ref;
            print header('application/json', '200 Accepted');
            print $json_str;
            exit;
        } else {
            return $hash_ref;
        }
    }
}

sub get_related_posts_titles {
    my $post_id = shift;

    if ( !StrNumUtils::is_numeric($post_id) ) {
        Error::report_error("400", "Invalid post ID.", "ID is not numeric.");
    }

    if ( !defined($post_id) || length($post_id) < 1 )  { 
        Error::report_error("400", "Invalid post ID.", "ID is missing.");
    }

    my $hash_ref = _get_post($post_id);

    if ( !$hash_ref ) {
        Error::report_error("404", "Post unavailable.", "Post ID not found");
    }

    $hash_ref->{status}           = 200;
    $hash_ref->{description}      = "OK";

    my @related_posts = RelatedPosts::get_related_posts($hash_ref->{post_id}, $hash_ref->{tags});
    $hash_ref->{related_posts_count}  = @related_posts;
    $hash_ref->{related_posts_titles} = \@related_posts;

    delete($hash_ref->{parent_id});
    delete($hash_ref->{author_id});
    delete($hash_ref->{post_type});
    delete($hash_ref->{post_status});
    delete($hash_ref->{post_digest});
    delete($hash_ref->{markup_text});
    delete($hash_ref->{formatted_text});

    my $json_str = encode_json $hash_ref;
    print header('application/json', '200 Accepted');
    print $json_str;
    exit;
}

sub _get_post {
    my $post_id        = shift;

    my $hash_ref;

    my $offset = Utils::get_time_offset();

    my $db = Db->new($pt_db_catalog, $pt_db_user_id, $pt_db_password);
    Error::report_error("500", "Error connecting to database.", $db->errstr) if $db->err;

    my $where_string = "a.post_id=$post_id and a.post_status in ('o','v') ";
    if ( !StrNumUtils::is_numeric($post_id) ) {
        my $uri_title = $db->quote($post_id);
        $where_string = "a.uri_title=$uri_title and a.post_status='o' ";
    }
    
    my $sql = <<EOSQL;
        select a.post_id, a.parent_id, a.title, a.uri_title, 
         a.markup_text, a.formatted_text, a.post_type,
         a.post_status, a.author_id, a.created_date,
         a.modified_date, a.version, a.post_digest, a.tags, 
         date_format(date_add(a.modified_date, interval $offset hour), '%b %d, %Y') as formatted_modified_date,
         date_format(date_add(a.created_date,  interval $offset hour), '%b %d, %Y') as formatted_created_date,
         date_format(date_add(a.modified_date, interval $offset hour), '%r')        as formatted_modified_time,
         date_format(date_add(a.created_date,  interval $offset hour), '%r')        as formatted_created_time,
         a.edit_reason, u.user_name as author_name
        from $dbtable_posts a, $dbtable_users u 
        where $where_string and a.post_type in ('article','draft','note') and a.author_id=u.user_id
EOSQL

# date_format(date_add(a.modified_date, interval $offset hour), '%r')        as formatted_modified_time,
# date_format(date_add(a.created_date,  interval $offset hour), '%r')        as formatted_created_time,
# date_format(date_add(a.modified_date, interval $offset hour), '%d%b%Y')    as formatted_urldate, 

    $db->execute($sql);
    Error::report_error("500", "Error executing SQL.", $db->errstr) if $db->err;

    # while ( $db->fetchrow ) {
    #    $hash{post_id}      = $db->getcol("post_id");
    #}
    $hash_ref  = $db->gethashref($sql);
    Error::report_error("500", "Error retrieving data from database.", $db->errstr) if $db->err;

    $db->disconnect();
    Error::report_error("500", "Error disconnecting from database.", $db->errstr) if $db->err;

    return $hash_ref;
}


1;

