package PostStatus;

use strict;

use JSON::PP;
use CGI qw(:standard);
use Config::Config;
use JRS::StrNumUtils;
use API::Error;
use API::Db;

my $pt_db_source       = Config::get_value_for("database_host");
my $pt_db_catalog      = Config::get_value_for("database_name");
my $pt_db_user_id      = Config::get_value_for("database_username");
my $pt_db_password     = Config::get_value_for("database_password");

my $dbtable_users      = Config::get_value_for("dbtable_users");
my $dbtable_tags       = Config::get_value_for("dbtable_tags");
my $dbtable_posts   = Config::get_value_for("dbtable_posts");

sub change_post_status {
    my $post_action      = shift;
    my $post_id          = shift;
    my $logged_in_user_id   = shift;

    if ( !StrNumUtils::is_numeric($post_id) ) {
        Error::report_error("404", "Could not perform requested action.", "Post ID is missing.");
    }

    if ( !$logged_in_user_id or !StrNumUtils::is_numeric($logged_in_user_id) ) {
        Error::report_error("404", "Could not perform requested action.", "User not logged in.");
    }

    if ( $post_action eq "delete" ) {
        _change_post_status($post_id, $logged_in_user_id, "o", "d");
    } elsif ( $post_action eq "undelete" ) {
        _change_post_status($post_id, $logged_in_user_id, "d", "o");
    } else {
        Error::report_error("404", "Invalid request.", "No action given.");
    }

    my $hash_ref;
    $hash_ref->{status}           = 200;
    $hash_ref->{description}      = "OK";
    my $json_str = encode_json $hash_ref;
    print header('application/json', '200 Accepted');
    print $json_str;
    exit;
}


sub _change_post_status {
    my $post_id       = shift;
    my $user_id          = shift;
    my $current_status   = shift;
    my $new_status       = shift;

    my $sql;
    my $tag_list_str;

    my $db = Db->new($pt_db_catalog, $pt_db_user_id, $pt_db_password);
    Error::report_error("500", "Error connecting to database.", $db->errstr) if $db->err;

    $sql = "select post_id, tags from $dbtable_posts where post_id=$post_id and author_id=$user_id and post_status='$current_status' ";
    $db->execute($sql);
    Error::report_error("500", "Error retrieving data from database.", $db->errstr) if $db->err;

    if ( !$db->fetchrow ) {
        $db->disconnect;
        Error::report_error("404", "Invalid action performed.", "Content does not exist.");
    } else {
        $tag_list_str = $db->getcol("tags");
    }

    $sql = "update $dbtable_posts set post_status='$new_status' where post_id=$post_id and author_id=$user_id";
    $db->execute($sql);
    Error::report_error("500", "Error updating database.", $db->errstr) if $db->err;

    if ( $tag_list_str ) {
        # remove beginning and ending pipe delimeter to make a proper delimited string
        $tag_list_str =~ s/^\|//;
        $tag_list_str =~ s/\|$//;
        my @tags = split(/\|/, $tag_list_str);
        foreach (@tags) {
            my $tag = $_;
            $tag = $db->quote($tag);
            if ( $tag ) {
                $sql = "update $dbtable_tags set tag_status='$new_status' where post_id=$post_id and tag_name=$tag";
                $db->execute($sql);
                Error::report_error("500", "Error updating database.", $db->errstr) if $db->err;
            }
        }
    }

    $db->disconnect;
    Error::report_error("500", "Error disconnecting from database.", $db->errstr) if $db->err;
}

1;




