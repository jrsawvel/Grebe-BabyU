package CompareVersions;

use strict;

use Algorithm::Diff;
use HTML::Entities;
use JSON::PP;
use CGI qw(:standard);
use JRS::StrNumUtils;
use Config::Config;
use API::Error;
use API::Db;
use API::GetPost;

my $pt_db_source       = Config::get_value_for("database_host");
my $pt_db_catalog      = Config::get_value_for("database_name");
my $pt_db_user_id      = Config::get_value_for("database_username");
my $pt_db_password     = Config::get_value_for("database_password");

my $dbtable_posts   = Config::get_value_for("dbtable_posts");

sub compare_versions {
    my $left_id  = shift;
    my $right_id = shift;

    if ( !defined($right_id) or length($right_id) < 1 or !defined($left_id) or length($left_id) < 1 ) {
        Error::report_error("400", "Invalid post ID(s).", "One or more IDs were missing.");
    }

    if ( !StrNumUtils::is_numeric($right_id) or !StrNumUtils::is_numeric($left_id) ) {
        Error::report_error("400", "Invalid post ID(s).", "One or more IDs were not numeric.");
    }

    my %version_data = _get_compare_info($left_id, $right_id);
    if ( !%version_data ) {
        Error::report_error("400", "Invalid comparison.", "Cannot access one or more of the posts.");
    }

    my @compare_results = _compare_versions($version_data{left_content}, $version_data{right_content});

    delete($version_data{left_content});
    delete($version_data{right_content});

    my $post_hash = GetPost::_get_post($version_data{left_parent_id});
    if ( !$post_hash ) {
        Error::report_error("404", "Post unavailable.", "Post ID not found");
    }

    my $hash_ref;
    
    $hash_ref->{top_version}      = $post_hash;
    $hash_ref->{version_data}     = \%version_data;
    $hash_ref->{compare_results}  = \@compare_results;
    $hash_ref->{status}           = 200;
    $hash_ref->{description}      = "OK";

    my $json_str = encode_json $hash_ref;

    print header('application/json', '200 Accepted');
    print $json_str;
    exit;
}

sub _get_compare_info {
    my $leftid  = shift;
    my $rightid = shift;

    my $offset = Utils::get_time_offset();

    my %compare = ();

    my $left_authorid = 0;
    my $right_authorid = 0;

    my $db = Db->new($pt_db_catalog, $pt_db_user_id, $pt_db_password);
    Error::report_error("500", "Error connecting to database.", $db->errstr) if $db->err;

    my $sql = "select post_id, parent_id, title, uri_title, author_id, markup_text, version, ";
    $sql .= "date_format(date_add(modified_date, interval $offset hour), '%b %d, %Y') as version_date, ";
    $sql .= "date_format(date_add(modified_date, interval $offset hour), '%r') as version_time ";
    $sql .= "from $dbtable_posts where post_id=$leftid"; 
    $db->execute($sql);
    Error::report_error("500", "Error executing SQL", $db->errstr) if $db->err;

    if ( $db->fetchrow ) {
        $compare{left_post_id}= $db->getcol("post_id");
        $compare{left_parent_id} = $db->getcol("parent_id");
        $compare{left_title}     = $db->getcol("title");
        $left_authorid           = $db->getcol("author_id");
        $compare{left_uri_title} = $db->getcol("uri_title");
        $compare{left_content}   = $db->getcol("markup_text");
        $compare{left_version}   = $db->getcol("version");
        $compare{left_date}      = $db->getcol("version_date");
        $compare{left_time}      = lc($db->getcol("version_time"));
    }
    Error::report_error("500", "Error retrieving data from database.", $db->errstr) if $db->err;

    $sql = "select post_id, parent_id, title, uri_title, author_id, markup_text, version, ";
    $sql .= "date_format(date_add(modified_date, interval $offset hour), '%b %d, %Y') as version_date, ";
    $sql .= "date_format(date_add(modified_date, interval $offset hour), '%r') as version_time ";
    $sql .= "from $dbtable_posts where post_id=$rightid";
    $db->execute($sql);
    Error::report_error("500", "Error executing SQL", $db->errstr) if $db->err;

    if ( $db->fetchrow ) {
        $compare{right_post_id} = $db->getcol("post_id");
        $compare{right_parent_id} = $db->getcol("parent_id");
        $compare{right_title}     = $db->getcol("title");
        $right_authorid           = $db->getcol("author_id");
        $compare{right_uri_title} = $db->getcol("uri_title");
        $compare{right_content}   = $db->getcol("markup_text");
        $compare{right_version}   = $db->getcol("version");
        $compare{right_date}      = $db->getcol("version_date");
        $compare{right_time}      = lc($db->getcol("version_time"));
    }

    $db->disconnect;
    Error::report_error("500", "Error disconnecting from database.", $db->errstr) if $db->err;

    # currently, only one person can edit a blog post. 
    # maybe later, multi-authoring will be permitted.
    if ( $right_authorid != $left_authorid ) {
        %compare = ();
    } 

    return %compare;
}

sub _compare_versions {
    my $leftcontent  = shift;
    my $rightcontent = shift;

    my @loop_data = ();

    my @left  = split /[\n]/, $leftcontent;
    my @right = split /[\n]/, $rightcontent;

    # sdiff returns an array of arrays
    my @sdiffs = Algorithm::Diff::sdiff(\@left, \@right);

    # first element is the mod indicator.
    # second element contains a hunk of content from the or older version (left)
    # third element contains a hunk of content from the or newer version (right)
    # the mods are based upon how the right side (newer) compares to the left (older)

    # modification indicators
    #  'added'      => '+',
    #  'removed'    => '-',
    #  'unmodified' => 'u',
    #  'changed'    => 'c',

    foreach my $arref (@sdiffs) {
        my %hash = ();

        $hash{leftdiffclass}  = "unmodified";
        $hash{rightdiffclass} = "unmodified";

        if ( $arref->[0] eq '+' ) {
            $hash{rightdiffclass} = "added";
        } elsif ( $arref->[0] eq '-' ) {
            $hash{leftdiffclass}  = "removed";
        } elsif ( $arref->[0] eq 'c' ) {
            $hash{leftdiffclass}  = "changed";
            $hash{rightdiffclass} = "changed";
        }

        $hash{modindicator} = $arref->[0];
        
        $hash{left}       = encode_entities(StrNumUtils::trim_spaces($arref->[1]));
        $hash{right}      = encode_entities(StrNumUtils::trim_spaces($arref->[2]));

        $hash{left}  = "&nbsp;" if ( length($hash{left} ) < 1 );
        $hash{right} = "&nbsp;" if ( length($hash{right}) < 1 );

        push(@loop_data, \%hash);
    }

    return @loop_data;
}

1;
