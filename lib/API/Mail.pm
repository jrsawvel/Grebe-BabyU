package Mail;

use strict;
use warnings;

use WWW::Mailgun;

sub send_passwordless_login_link {
    my $email_rcpt      = shift;
    my $user_digest     = shift;
    my $password_digest = shift;
    my $client_url      = shift;

    my $date_time = Utils::create_datetime_stamp();

    my $mailgun_api_key = Config::get_value_for("mailgun_api_key");
    my $mailgun_domain  = Config::get_value_for("mailgun_domain");
    my $mailgun_from    = Config::get_value_for("mailgun_from");

    my $home_page = Config::get_value_for("home_page");
    my $link      = "$home_page/nopwdlogin/$user_digest/$password_digest";

    if ( $client_url ) {
        $link = "$client_url/nopwdlogin/$user_digest/$password_digest";
    }

    my $site_name = Config::get_value_for("site_name");
    my $subject = "$site_name Login Link - $date_time UTC";

    my $message = "Clink or copy link to log into the site.\n\n$link\n";
             

    my $mg = WWW::Mailgun->new({ 
        key    => "$mailgun_api_key",
        domain => "$mailgun_domain",
        from   => "$mailgun_from"
    });

    $mg->send({
          to      => "<$email_rcpt>",
          subject => "$subject",
          text    => "$message"
    });

}

1;

