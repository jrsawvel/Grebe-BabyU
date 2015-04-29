package NoPwdLogin;

use strict;
use warnings;

use JSON::PP;
use CGI qw(:standard);
use JRS::DateTimeFormatter;
use JRS::StrNumUtils;
use Config::Config;
use API::DigestMD5;
use API::Db;
use API::Utils;
use API::Error;

my $pt_db_source       = Config::get_value_for("database_host");
my $pt_db_catalog      = Config::get_value_for("database_name");
my $pt_db_user_id      = Config::get_value_for("database_username");
my $pt_db_password     = Config::get_value_for("database_password");

my $dbtable_users      = Config::get_value_for("dbtable_users");
my $dbtable_sessionids = Config::get_value_for("dbtable_sessionids");

sub no_password_login {
    my $json_str = shift;

    if ( !Config::get_value_for("passwordless_login") ) {
        Error::report_error("404", "Invalid login.", "Action unsupported.");
    }

    my $error_exists = 0;

    my $json_params  = decode_json $json_str;

    my $user_digest     = $json_params->{user_digest};
    my $password_digest = $json_params->{password_digest};

#  Error::report_error("400", "email=$email", "password=$password");

    my %hash = _verify_no_password_login($user_digest, $password_digest);

    if ( !%hash ) {
        Error::report_error("404", "Invalid login.", "Username or password was not found in database.");
    }

    $hash{status}           = 200;
    $hash{description}      = "OK";
    my $json_return_str = encode_json \%hash;
    print header('application/json', '200 Accepted');
    print $json_return_str;
    exit;
}

sub _verify_no_password_login {
    my $user_digest     = shift;
    my $password_digest = shift;

    my $sessionid = "";
    my $sql = "";
    my %hash;

    my $current_datetime = Utils::create_datetime_stamp();

    my $multiple_sessionids = Config::get_value_for("multiple_sessionids");

    my $db = Db->new($pt_db_catalog, $pt_db_user_id, $pt_db_password);
    Error::report_error("500", "Error connecting to database.", $db->errstr) if $db->err;
   
    my $user_digest     = $db->quote($user_digest); 
    my $password_digest = $db->quote($password_digest); 
    $sql = "select user_id, user_name, password, created_date, orig_email from $dbtable_users where user_digest=$user_digest and password=$password_digest and user_status='o' and login_link_status='p'";

    $db->execute($sql);
    Error::report_error("500", "Error executing SQL", $db->errstr) if $db->err;

    my $datetime     = "";
    my $md5_password = "";
    my $orig_email   = "";

    if ( $db->fetchrow ) {
        $hash{user_id}     = $db->getcol("user_id");
        $hash{user_name}   = $db->getcol("user_name");
        $md5_password      = $db->getcol("password");
        $datetime          = $db->getcol("created_date");
        $orig_email        = $db->getcol("orig_email");

        my $tmp_dt = DateTimeFormatter::create_date_time_stamp_utc("(yearfull)-(0monthnum)-(0daynum) (24hr):(0min):(0sec)"); # db date format in gmt:  2013-07-17 21:15:34
        $hash{session_id} = DigestMD5::create($hash{user_name}, $orig_email, $md5_password, $datetime, $tmp_dt);
        $hash{session_id} =~ s|[^\w]+||g;
    } else {
        $db->disconnect;
        Error::report_error("500", "Error disconnecting from database.", $db->errstr) if $db->err;
        %hash = ();
        return %hash; 
    }

    Error::report_error("500", "Error retrieving data from database.", $db->errstr) if $db->err;

   my $sessionid = $db->quote($hash{session_id});
   if ( $multiple_sessionids ) {
       $sql = "insert into $dbtable_sessionids (user_id, session_id, created_date, session_status)";
       $sql .= " values ($hash{user_id}, $sessionid, '$current_datetime', 'o')";
       $db->execute($sql);
       Error::report_error("500", "Error executing SQL", $db->errstr) if $db->err;
       $sql = "update $dbtable_users set login_link_status='d' where user_id=$hash{user_id}";
   } else {
       $sql = "insert into $dbtable_sessionids (user_id, session_id, created_date, session_status)";
       $sql .= " values ($hash{user_id}, $sessionid, '$current_datetime', 'o')";
       $db->execute($sql);
       Error::report_error("500", "Error executing SQL", $db->errstr) if $db->err;
       $sql = "update $dbtable_users set session_id=$sessionid, login_link_status='d' where user_id=$hash{user_id}";
   }
   $db->execute($sql);
   Error::report_error("500", "Error executing SQL", $db->errstr) if $db->err;

    $db->disconnect;
    Error::report_error("500", "Error disconnecting from database.", $db->errstr) if $db->err;

    return %hash;
}

1;

