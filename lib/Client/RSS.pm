package RSS;

use strict;

use HTML::Entities;
use CPAN::XML::FeedPP;
use JRS::StrNumUtils;
use JRS::DateTimeUtils;
use JRS::DateTimeFormatter;

sub display_rss {
    my $articles_ref = shift;
    my $description  = shift;
    my $search_url   = shift;

    my $cgi_app          = Config::get_value_for("cgi_app");
    my $app_name         = Config::get_value_for("app_name");
    my $home_page        = "http://" . Config::get_value_for("domain_name");
    my $site_name        = Config::get_value_for("site_name");
    my $site_description = Config::get_value_for("site_description");

    # Mon, 16 Jun 2014 17:37:35 GMT
    my $current_date_time = DateTimeFormatter::create_date_time_stamp_utc("(dayname), (0daynum) (monthname) (yearfull) (24hr):(0min):(0sec) GMT");

    my @rss_articles = ();
    foreach my $hash_ref ( @$articles_ref ) {
        my %hash = ();

        $hash{title}        = encode_entities($hash_ref->{title});

        $hash{posttext} = $hash_ref->{formatted_text};
        # 13jun2014 - leave html tags in rss for now, i guess.
        $hash{posttext} = StrNumUtils::trim_spaces($hash{posttext});
        $hash{posttext} = StrNumUtils::remove_newline($hash{posttext}); # not working?? - todo - verify - plus why remove newline?
        $hash{posttext} = encode_entities($hash{posttext});


        my $md = $hash_ref->{modified_date};
        $hash{modified_date} = DateTimeFormatter::create_date_time_stamp_utc(DateTimeUtils::convert_date_to_epoch($hash_ref->{modified_date}), "(dayname), (0daynum) (monthname) (yearfull) (24hr):(0min):(0sec) GMT");
        
        $hash{articleid}    = $hash_ref->{post_id};

        $hash{author}       = $hash_ref->{user_name};
        $hash{cgi_app}      = $cgi_app;
        $hash{home_page}    = $home_page;
        $hash{urltitle}     = $hash_ref->{uri_title};

        push(@rss_articles, \%hash);
    }

    my $t = Page->new("rss");
    $t->set_template_loop_data("article_loop", \@rss_articles);

    $t->set_template_variable("description", $description);
    $t->set_template_variable("app_name", $app_name);
    $t->set_template_variable("site_name", $site_name);
    $t->set_template_variable("site_description", $site_description);
    $t->set_template_variable("current_date_time", $current_date_time);
    $t->set_template_variable("link", $home_page . $cgi_app . $search_url);

    $t->print_template("Content-type: text/xml");
}

1;
