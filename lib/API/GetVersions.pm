package GetVersions;

use strict;

use JSON::PP;
use CGI qw(:standard);
use Config::Config;
use JRS::StrNumUtils;
use API::Error;
use API::Db;
use API::Utils;
use API::GetPost;

my $pt_db_source       = Config::get_value_for("database_host");
my $pt_db_catalog      = Config::get_value_for("database_name");
my $pt_db_user_id      = Config::get_value_for("database_username");
my $pt_db_password     = Config::get_value_for("database_password");

my $dbtable_posts   = Config::get_value_for("dbtable_posts");
my $dbtable_users      = Config::get_value_for("dbtable_users");

sub get_versions {
    my $post_id = shift;

    if ( !defined($post_id) || length($post_id) < 1 )  { 
        Error::report_error("400", "Invalid post ID.", "ID is missing.");
    }

    if ( !StrNumUtils::is_numeric($post_id) ) {
        Error::report_error("400", "Invalid post ID.", "ID is missing.");
    }

#    if ( !StrNumUtils::is_numeric($post_id) ) {
#        my $post_hash = GetPost::_get_post($post_id);
#        if ( !$post_hash ) {
#            Error::report_error("404", "Post unavailable.", "Post ID not found");
#        }
#        $post_id = $post_hash->{post_id};
#    }
    
    my $post_hash = GetPost::_get_post($post_id);
    if ( !$post_hash ) {
        Error::report_error("404", "Post unavailable.", "Post ID not found");
    }

    my @version_list = _get_version_list($post_hash->{post_id});

    my $hash_ref;

    $hash_ref->{version_list}            = \@version_list;
    $hash_ref->{status}                  = 200;
    $hash_ref->{description}             = "OK";
    $hash_ref->{post_id}              = $post_hash->{post_id};
    $hash_ref->{title}                   = $post_hash->{title};
    $hash_ref->{uri_title}               = $post_hash->{uri_title};
    $hash_ref->{version}                 = $post_hash->{version};
    $hash_ref->{author_name}             = $post_hash->{author_name};
    $hash_ref->{formatted_modified_date} = $post_hash->{formatted_modified_date};
    $hash_ref->{formatted_modified_time} = $post_hash->{formatted_modified_time};
    $hash_ref->{edit_reason}             = $post_hash->{edit_reason};

    my $json_str = encode_json $hash_ref;

    print header('application/json', '200 Accepted');
    print $json_str;
    exit;
}

sub _get_version_list {
    my $post_id = shift;

    my $offset = Utils::get_time_offset();

    my $db = Db->new($pt_db_catalog, $pt_db_user_id, $pt_db_password);
    Error::report_error("500", "Error connecting to database.", $db->errstr) if $db->err;

    my $sql = <<EOSQL;
        select a.post_id, a.uri_title, 
          date_format(date_add(a.modified_date, interval $offset hour), '%b %d, %Y') as version_date, 
          date_format(date_add(a.modified_date, interval $offset hour), '%r') as version_time, 
          a.version, u.user_name as author_name, a.edit_reason from $dbtable_posts a, $dbtable_users u 
          where  a.parent_id=$post_id  and a.post_status='v' and a.author_id=u.user_id 
          order by a.version desc
EOSQL
#          where ( (a.parent_id=$post_id  and a.post_status='v') or (a.post_id=$post_id and a.parent_id=0 and a.post_status='o') ) and a.author_id=u.user_id 

    $db->execute($sql);
    Error::report_error("500", "Error executing SQL", $db->errstr) if $db->err;

    my @loop_data = $db->gethashes($sql);
    Error::report_error("500", "Error retrieving data from database.", $db->errstr) if $db->err;

    $db->disconnect;
    Error::report_error("500", "Error disconnecting from database.", $db->errstr) if $db->err;

    return @loop_data;
}

1;
