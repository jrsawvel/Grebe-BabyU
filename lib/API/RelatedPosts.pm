package RelatedPosts;

use strict;
use warnings;

use API::Utils;

my $pt_db_source       = Config::get_value_for("database_host");
my $pt_db_catalog      = Config::get_value_for("database_name");
my $pt_db_user_id      = Config::get_value_for("database_username");
my $pt_db_password     = Config::get_value_for("database_password");

my $dbtable_posts   = Config::get_value_for("dbtable_posts");
my $dbtable_tags       = Config::get_value_for("dbtable_tags");

# related post SQL from Pete Freitag's blog post at
# http://www.petefreitag.com/item/315.cfm
sub get_related_posts {
    my $post_id = shift;
    my $tag_str    = shift;

    my $offset = Utils::get_time_offset();

    # if at least one tag, then string will contain at a minimum
    #     |x|
    my @loop_data = ();
    return @loop_data if ( !$tag_str or (length($tag_str) < 3) );

    my @tagnames = ();
    my $instr = "";
    $tag_str =~ s/^\|//;
    $tag_str =~ s/\|$//;
    if ( @tagnames = split(/\|/, $tag_str) ) {
        foreach (@tagnames) {
            $instr .= "'$_'," if ( $_ );
        }
    }
    $instr =~ s/,$//;

    my $db = Db->new($pt_db_catalog, $pt_db_user_id, $pt_db_password);
    Error::report_error("500", "Error connecting to database.", $db->errstr) if $db->err;

    my $sql = <<EOSQL; 
    SELECT a.post_id, a.title, a.uri_title, 
      DATE_FORMAT(DATE_ADD(a.modified_date, interval $offset hour), '%b %d, %Y') AS formatted_modified_date,
      COUNT(t.post_id) AS wt
      FROM $dbtable_posts AS a, $dbtable_tags AS t
      WHERE t.post_id <> $post_id 
      AND t.tag_name IN ($instr)
      AND a.post_id = t.post_id
      AND a.post_status in ('o')  
      AND a.post_type in ('article')
      GROUP BY a.title, a.post_id
      HAVING wt > 1
      ORDER BY wt DESC 
EOSQL

    $db->execute($sql);
    Error::report_error("500", "(66) Error executing SQL", $db->errstr) if $db->err;

    @loop_data = $db->gethashes($sql);
    Error::report_error("system", "Error retrieving data from database.", $db->errstr) if $db->err;

    $db->disconnect;
    Error::report_error("system", "Error disconnecting from database.", $db->errstr) if $db->err;

    return @loop_data;
}

1;

