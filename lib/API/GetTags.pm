package GetTags;

use strict;

use JSON::PP;
use CGI qw(:standard);
use Config::Config;
use API::Error;
use API::Db;

my $pt_db_source       = Config::get_value_for("database_host");
my $pt_db_catalog      = Config::get_value_for("database_name");
my $pt_db_user_id      = Config::get_value_for("database_username");
my $pt_db_password     = Config::get_value_for("database_password");

my $dbtable_tags       = Config::get_value_for("dbtable_tags");

sub get_tags {

    my $q = new CGI;

    my $sort_by = $q->param("sortby");

    if ( $sort_by ne "name" and $sort_by ne "count" ) {
        Error::report_error("400", "Could not retrieve list of tags.", "Invalid tag display option provided.");
    }

    my @tag_list = _get_tag_list($sort_by);

    my $hash_ref;

    $hash_ref->{total_unique_tags}= @tag_list;
    $hash_ref->{tag_list}         = \@tag_list;
    $hash_ref->{sort_by}          = $sort_by;
    $hash_ref->{status}           = 200;
    $hash_ref->{description}      = "OK";

    my $json_str = encode_json $hash_ref;

    print header('application/json', '200 Accepted');
    print $json_str;
    exit;
}

sub _get_tag_list {
    my $order_by = shift;

    my $where_str = "where tag_status='o'";

    my $order_by_str = "";
    if ( $order_by eq "count" ) {
        $order_by_str = " order by tag_count desc";
    } 

    my $db = Db->new($pt_db_catalog, $pt_db_user_id, $pt_db_password);
    Error::report_error("500", "Error connecting to database.", $db->errstr) if $db->err;

    my $sql;
    $sql  = "select tag_name, count(*) as tag_count from $dbtable_tags $where_str group by tag_name $order_by_str";
    $db->execute($sql);
    Error::report_error("500", "Error executing SQL", $db->errstr) if $db->err;

#    while ( $db->fetchrow ) {
#        my %hash;
#        $hash{tag_name}          = $db->getcol("tag_name");
#        $hash{tag_count}         = $db->getcol("tag_count");
#        push(@loop_data, \%hash);
#    }
    my @loop_data = $db->gethashes($sql);
    Error::report_error("500", "Error retrieving data from database.", $db->errstr) if $db->err;

    $db->disconnect;
    Error::report_error("500", "Error disconnecting from database.", $db->errstr) if $db->err;

    return @loop_data;
}



1;
