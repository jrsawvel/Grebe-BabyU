package CreatePost;

use strict;

use JSON::PP;
use URI::Escape;
use HTML::Entities;
use Encode qw(decode encode);
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
use API::GetPost;
use API::WriteTemplateMarkup;
use API::GetUser;
use API::Stream;

my $pt_db_source       = Config::get_value_for("database_host");
my $pt_db_catalog      = Config::get_value_for("database_name");
my $pt_db_user_id      = Config::get_value_for("database_username");
my $pt_db_password     = Config::get_value_for("database_password");

my $dbtable_posts      = Config::get_value_for("dbtable_posts");
my $dbtable_users      = Config::get_value_for("dbtable_users");
my $dbtable_tags       = Config::get_value_for("dbtable_tags");

sub create_post {
    my $tmp_hash = shift;
    my $logged_in_user_name = shift;
    my $logged_in_user_id =  shift;

    my $err_msg;
    undef $err_msg;

    my $q = new CGI;

    my $json_params  = decode_json $q->param("json");

    my $user_submitted_post_text = $json_params->{post_text};

    my $submit_type = $json_params->{submit_type}; # Preview or Post

    my $markup_text    = StrNumUtils::trim_spaces($user_submitted_post_text);

    if ( !defined($markup_text) || length($markup_text) < 1 )  { 
       $err_msg .= "You must enter text.";
    } 

    if ( $submit_type ne "Preview" and $submit_type ne "Post" ) {
        $err_msg .= "Invalid submit type given.";
    }

    my $formtype = $json_params->{"form_type"};
    if ( $formtype eq "ajax" ) {
        $markup_text = URI::Escape::JavaScript::unescape($markup_text);
        $markup_text = HTML::Entities::encode($markup_text,'^\n\x20-\x25\x27-\x7e');
    } 

    my $o = PostTitle->new();
#    $o->set_logged_in_username(User::get_logged_in_username()); -- for namespace enforcement, but not used for now
    $o->process_title($markup_text);
    my $tmp_markup_text   = $o->get_after_title_markup();
    my $title             = $o->get_title();
    my $post_title        = $o->get_post_title();
    my $content_type      = $o->get_content_type();
    my $markup_type       = $o->get_markup_type();
    $err_msg             .= $o->get_error_string() if $o->is_error();

# $err_msg = "debug title=[$title] post_title=[$post_title] tmp_markup_text=[$tmp_markup_text]";

    if ( defined($err_msg) ) {
        my %hash;
        $hash{status}         = 400;
        $hash{description}    = "Bad Request";
        $hash{user_message}   = $err_msg;
        $hash{system_message} = $err_msg;
        $hash{post_text}      = $user_submitted_post_text;
        my $json_str = encode_json \%hash;
        print header('application/json', '400 Accepted');
        print $json_str;
        exit;
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

    my $post_id = 0;

    if ( $submit_type eq "Post" ) {
        $post_id = _create_post($logged_in_user_id, $post_title, $uri_title, $markup_text, $formatted_text, $content_type, $tag_list_str, $block_id);
        $hash{post_id}       = $post_id;
        if ( $formtype eq "ajax" ) {
            $hash{formatted_text} = $formatted_text;
            $hash{title}          = $post_title;
            $hash{post_type}      = $content_type;
            my $post_hash = GetPost::_get_post($post_id);
            $hash{post_digest}    = $post_hash->{post_digest};
        } 
        WriteTemplateMarkup::output_template_and_markup($logged_in_user_id, $post_id); 

        # begin change 7Oct2014
        if ( $content_type eq "note" ) {
            # return note stream home page
            my $user_ref   = GetUser::_get_user($logged_in_user_name, $logged_in_user_name, $logged_in_user_id, "yes", 200); 
            my %uri_values = ("page_num" => 1, "filter_by_author_name" => 1,  "author_name" => $logged_in_user_name, "post_type" => "note");
            my $sql        =  Stream::_create_posts_sql(\%uri_values, $logged_in_user_id, $user_ref);
            my @posts      =  Stream::_get_stream($sql);
            @posts         =  Stream::_format_posts(\@posts, $logged_in_user_id);
            $hash{notes_homepage}  =  Stream::_format_json_posts(\@posts, $logged_in_user_id, \%uri_values, $user_ref);
        }
        # end change 7Oct2014
    } elsif ( $submit_type eq "Preview" ) {
        $hash{formatted_text} = $formatted_text;
        $hash{title} = $post_title;
        $hash{post_type} = $content_type;
    }

    $hash{status}           = 200;
    $hash{description}      = "Created";
    my $json_str = encode_json \%hash;
    print header('application/json', '200 Accepted');
    print $json_str;

    exit;
}

sub _create_post {
    my $author_id      = shift;
    my $title          = shift;
    my $uri_title      = shift;
    my $markup_text    = shift;
    my $formatted_text = shift;
    my $content_type   = shift;
    my $tag_list_str   = shift;
    my $block_id       = shift;

    my $post_type; 
    my $post_status = "o";
    my $parent_id      = 0;

    my $date_time = Utils::create_datetime_stamp();

    if ( $content_type eq "article" ) {
        $post_type = "article";
        if ( Utils::get_power_command_on_off_setting_for("draft", $markup_text, 0) ) {
            $post_type = "draft";
        }
    } else {
        $post_type = "note";
    }

    my $db = Db->new($pt_db_catalog, $pt_db_user_id, $pt_db_password);
    Error::report_error("500", "Error connecting to database.", $db->errstr) if $db->err;

    $title          = $db->quote($title);
    $markup_text    = $db->quote($markup_text);
    $formatted_text = $db->quote($formatted_text);
    $uri_title      = $db->quote($uri_title);
    my $quoted_tag_list_str   = $db->quote($tag_list_str);

    # create post digest
    my $md5 = Digest::MD5->new;
    $md5->add(Utils::otp_encrypt_decrypt($markup_text, $date_time, "enc"), $author_id, $date_time);
    my $post_digest = $md5->b64digest;
    $post_digest =~ s|[^\w]+||g;

    my $sql = <<EOSQL;
        insert into $dbtable_posts 
            (parent_id, title, uri_title, markup_text, formatted_text, 
              post_type, post_status, author_id, 
              created_date, modified_date, post_digest, tags, block_id)
        values 
            ($parent_id, $title, $uri_title, $markup_text, $formatted_text, 
              '$post_type', '$post_status', $author_id, 
              '$date_time', '$date_time', '$post_digest', $quoted_tag_list_str, $block_id) 
EOSQL

    my $post_id = $db->execute($sql);
    Error::report_error("500", "Error executing SQL.", $db->errstr) if $db->err;

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
            Error::report_error("500", "Error executing SQL.", $db->errstr) if $db->err;
        }
    }

    $db->disconnect;
    Error::report_error("500", "Error disconnecting from database.", $db->errstr) if $db->err;

    return $post_id;
}

1;

