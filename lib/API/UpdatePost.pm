package UpdatePost;

use strict;

use JSON::PP;
use HTML::Entities;
use Encode qw(decode encode);
use URI::Escape::JavaScript;
use CGI qw(:standard);
use CGI::Carp qw(fatalsToBrowser);
use Config::Config;
use JRS::StrNumUtils;
use API::Utils;
use API::Format;
use API::Error;
use API::DigestMD5;
use API::Db;
use API::PostTitle;
use API::WriteTemplateMarkup;
# use API::GetPost;

my $pt_db_source       = Config::get_value_for("database_host");
my $pt_db_catalog      = Config::get_value_for("database_name");
my $pt_db_user_id      = Config::get_value_for("database_username");
my $pt_db_password     = Config::get_value_for("database_password");

my $dbtable_posts   = Config::get_value_for("dbtable_posts");
my $dbtable_tags       = Config::get_value_for("dbtable_tags");

sub update_post {
    my $tmp_hash = shift;
    my $logged_in_user_name = shift;
    my $logged_in_user_id =  shift;

    my $err_msg;
    undef $err_msg;

    my $q = new CGI;

    my $json_params  = decode_json $q->param("json");

    my $user_submitted_post_text = $json_params->{post_text};
    my $post_id                  = $json_params->{post_id};
    my $post_digest              = $json_params->{post_digest};
    my $edit_reason              = $json_params->{edit_reason};
    my $submit_type              = $json_params->{submit_type}; # Preview or Update

    my $markup_text    = StrNumUtils::trim_spaces($user_submitted_post_text);

    if ( !defined($markup_text) || length($markup_text) < 1 )  { 
       $err_msg .= "You must enter text.";
    } 

    if ( !defined($post_id) || length($post_id) < 1 || !StrNumUtils::is_numeric($post_id) )  { 
       $err_msg .= "Missing post ID.";
    } 

    if ( !defined($post_digest) || length($post_digest) < 1 )  { 
       $err_msg .= "Missing post digest.";
    } 

    if ( $submit_type ne "Preview" and $submit_type ne "Update" ) {
        $err_msg .= "Invalid submit type given.";
    }

    my $formtype = $json_params->{"form_type"};
    if ( $formtype eq "ajax" ) {
        $markup_text = URI::Escape::JavaScript::unescape($markup_text);
        $markup_text = HTML::Entities::encode($markup_text,'^\n\x20-\x25\x27-\x7e');
    } 

#    } else {
#        $markup_text = Encode::decode_utf8($markup_text);
#        $markup_text = HTML::Entities::encode($markup_text,'^\n^\r\x20-\x25\x27-\x7e');
#    }

    my $o = PostTitle->new();
#    $o->set_logged_in_username(User::get_logged_in_username()); -- for namespace enforcement, but not used for now
    $o->set_post_id($post_id);
    $o->process_title($markup_text);
    my $tmp_markup_text   = $o->get_after_title_markup();
    my $title             = $o->get_title();
    my $post_title        = $o->get_post_title();
    my $content_type      = $o->get_content_type();
    my $markup_type       = $o->get_markup_type();
    $err_msg             .= $o->get_error_string() if $o->is_error();

    if ( defined($err_msg) ) {
        my %hash;
        $hash{status}         = 400;
        $hash{description}    = "Bad Request";
        $hash{user_message}   = $err_msg;
        $hash{system_message} = $err_msg;
        $hash{post_text}   = $user_submitted_post_text;
        my $json_str = encode_json \%hash;
        print header('application/json', '400 Accepted');
        print $json_str;
        exit;
    } 

    if ( $edit_reason ) {
        $edit_reason    = encode_entities($edit_reason, '<>');
    }

    my $tag_list_str = Format::create_tag_list_str($markup_text);

    my $formatted_text;

    my $block_id = Format::get_block_id($tmp_markup_text);

    if ( $content_type eq "article" ) {
        $formatted_text = Format::format_content($tmp_markup_text, $markup_type);
    } elsif ( $content_type eq "note" ) {
        $formatted_text = Format::format_content($markup_text, $markup_type);
    }

    my $uri_title = lc(Format::clean_title($post_title));

    my %hash;

    if ( $submit_type eq "Update" ) {
        $post_id = _update_post($logged_in_user_id, $post_title, $uri_title, $markup_text, $formatted_text, $content_type, $tag_list_str, $post_id, $post_digest, $edit_reason, $block_id);
        $hash{post_id}       = $post_id;
        if ( $formtype eq "ajax" ) {
            $hash{formatted_text} = $formatted_text;
            $hash{title}          = $post_title;
            $hash{post_type}      = $content_type;
            $hash{post_digest}    = $post_digest;
        }
        WriteTemplateMarkup::output_template_and_markup($logged_in_user_id, $post_id);
    } elsif ( $submit_type eq "Preview" ) {
        $hash{formatted_text} = $formatted_text;
        $hash{title}          = $post_title;
        $hash{post_type}      = $content_type;
        $hash{post_id}        = $post_id;
        $hash{post_digest}    = $post_digest;
        $hash{edit_reason}    = $edit_reason;
    }

    $hash{status}           = 201;
    $hash{description}      = "Updated";
    my $json_str = encode_json \%hash;
    print header('application/json', '201 Accepted');
    print $json_str;

    exit;
}

sub _update_post {
    my $author_id      = shift;
    my $title          = shift;
    my $uri_title      = shift;
    my $markup_text    = shift;
    my $formatted_text = shift;
    my $content_type   = shift;
    my $tag_list_str   = shift;
    my $post_id        = shift;
    my $post_digest    = shift;
    my $edit_reason    = shift;
    my $block_id       = shift;

    my $post_type   = "article";
    my $post_status = "o";
    my $parent_id   = 0;

    my $date_time = Utils::create_datetime_stamp();

    if ( !_is_updating_correct_post($post_id, $author_id, $post_digest) ) { 
        Error::report_error("400", "Error updating post.", "Access denied.");
    }

    my $aid = $post_id;
    $parent_id = _is_updating_an_older_version($post_id);
    $aid = $parent_id if ( $parent_id > 0 );

    if ( $content_type eq "article" ) {
        $post_type = "article";
        if ( Utils::get_power_command_on_off_setting_for("draft", $markup_text, 0) ) {
            $post_type = "draft";
        }
    } else {
        $post_type = "note";
    }

    my $sql;

    my $db = Db->new($pt_db_catalog, $pt_db_user_id, $pt_db_password);
    Error::report_error("500", "Error connecting to database.", $db->errstr) if $db->err;

    $title          = $db->quote($title);
    $markup_text    = $db->quote($markup_text);
    $formatted_text = $db->quote($formatted_text);
    $uri_title      = $db->quote($uri_title);
    $edit_reason    = $db->quote($edit_reason);
    my $quoted_tag_list_str   = $db->quote($tag_list_str);

    # make copy of most recent version.
    my %old;
    $sql =  "select post_id, title, uri_title, markup_text, formatted_text, ";
    $sql .= "post_type, post_status, author_id, created_date, modified_date, ";
    $sql .= "version, post_digest, edit_reason, tags, block_id "; 
    $sql .= "from $dbtable_posts where post_id=$aid";
    $db->execute($sql);
    Error::report_error("500", "Error executing SQL", $db->errstr) if $db->err;
    
    if ( $db->fetchrow ) {
        $old{parent_id}        = $db->getcol("post_id");
        $old{title}            = $db->quote($db->getcol("title"));
        $old{uri_title}        = $db->quote($db->getcol("uri_title"));
        $old{markup_text}      = $db->quote($db->getcol("markup_text"));
        $old{formatted_text}   = $db->quote($db->getcol("formatted_text"));
        $old{post_type}        = $db->getcol("post_type");
        $old{post_status}      = $db->getcol("post_status");
        $old{author_id}        = $db->getcol("author_id");
        $old{created_date}     = $db->getcol("created_date");
        $old{modified_date}    = $db->getcol("modified_date");
        $old{version}          = $db->getcol("version");
        $old{post_digest}      = $db->getcol("post_digest");
        $old{edit_reason}      = $db->quote($db->getcol("edit_reason"));
        $old{tags}             = $db->quote($db->getcol("tags"));
        $old{block_id}         = $db->getcol("block_id");
    }
    Error::report_error("500", "Error retrieving data from database. $sql", $db->errstr) if $db->err;

    my $status = 'v';  # previous version 
    $sql =  "insert into $dbtable_posts (parent_id, title, uri_title, markup_text, formatted_text, post_type, post_status, author_id, created_date, modified_date, version, post_digest,  edit_reason, tags, block_id)";
    $sql .= " values ($old{parent_id}, $old{title}, $old{uri_title}, $old{markup_text}, $old{formatted_text}, '$old{post_type}', '$status', $old{author_id}, '$old{created_date}', '$old{modified_date}', $old{version}, '$old{post_digest}', $old{edit_reason}, $old{tags}, $old{block_id})";

    $db->execute($sql);
    Error::report_error("500", "(28) Error executing SQL", $db->errstr) if $db->err;

    #####  todo create new content digest when post updated??? for now, no.

    # add new modified content
    my $version = $old{version} + 1;
    my $new_status = 'o';
    $sql = "update $dbtable_posts ";
    $sql .= " set title=$title, uri_title=$uri_title, markup_text=$markup_text, formatted_text=$formatted_text, post_type='$post_type', author_id=$author_id, modified_date='$date_time', post_status='$new_status', version=$version, edit_reason=$edit_reason, tags=$quoted_tag_list_str, block_id=$block_id ";
    $sql .= " where post_id=$aid";
    $db->execute($sql);
    Error::report_error("500", "(29) Error executing SQL", $db->errstr) if $db->err;

    # removed existing tags from table
    $sql = "delete from $dbtable_tags where post_id=$post_id";
    $db->execute($sql);
    Error::report_error("500", "Error connecting to database.", $db->errstr) if $db->err;
    # remove beginning and ending pipe delimeter to make a proper delimited string
    $tag_list_str =~ s/^\|//;
    $tag_list_str =~ s/\|$//;
    my @tags = split(/\|/, $tag_list_str);
    foreach (@tags) {
        my $tag = $_;
        $tag = $db->quote($tag);
        if ( $tag ) {
            $sql = "insert into $dbtable_tags (tag_name, post_id, tag_status, created_by, created_date) "; 
            $sql .= " values ($tag, $post_id, 'o', $author_id, '$date_time') "; 
            $db->execute($sql);
            Error::report_error("500", "Error executing SQL", $db->errstr) if $db->err;
        }
    }

    $db->disconnect;
    Error::report_error("500", "Error disconnecting from database.", $db->errstr) if $db->err;

    return $aid;

}

sub _is_updating_an_older_version {
    my $post_id = shift;

    my $parent_id = 0;

    my $db = Db->new($pt_db_catalog, $pt_db_user_id, $pt_db_password);
    Error::report_error("500", "Error connecting to database.", $db->errstr) if $db->err;

    # if updating an older version, the parentid should be >0 and status should = v 
    my $sql = "select parent_id from $dbtable_posts where post_id=$post_id and post_status='v'";
    $db->execute($sql);
    Error::report_error("500", "Error executing SQL", $db->errstr) if $db->err;

    if ( $db->fetchrow ) {
        $parent_id  = $db->getcol("parent_id");
    }
    Error::report_error("500", "Error retrieving data from database. $sql", $db->errstr) if $db->err;

    $db->disconnect;
    Error::report_error("500", "Error disconnecting from database.", $db->errstr) if $db->err;

    return $parent_id;
}

sub _is_updating_correct_post {
    my ($post_id, $author_id, $post_digest) = @_;

    my $return_value = 0;

    my $db = Db->new($pt_db_catalog, $pt_db_user_id, $pt_db_password);
    Error::report_error("500", "Error connecting to database.", $db->errstr) if $db->err;

    $post_digest = $db->quote($post_digest);

    my $sql = "select title from $dbtable_posts ";
    $sql .=   "where post_id=$post_id and author_id=$author_id and post_status in ('o','v') and post_digest=$post_digest"; 
    $db->execute($sql);

    if ( $db->fetchrow ) {
        $return_value = 1;
    }
    Error::report_error("500", "Error retrieving data from database. $sql", $db->errstr) if $db->err;

    $db->disconnect;
    Error::report_error("500", "Error disconnecting from database.", $db->errstr) if $db->err;

    return $return_value;
}

1;

