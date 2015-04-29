package WriteTemplateMarkup;

use strict;

use HTML::Entities;
use Redis;
use Cache::Memcached::libmemcached;
use JRS::Page;
use JRS::DateTimeFormatter;
use API::GetPost;
use API::Stream;
use LWP::Simple;

sub output_template_and_markup {
    my $logged_in_user_id = shift;
    my $post_id           = shift;
   
    my %user_auth;
    $user_auth{logged_in_user_id} = $logged_in_user_id;

    my $hash_ref = GetPost::get_post(\%user_auth, $post_id, "private");

    if ( Config::get_value_for("write_template") ) {
        my $html = _create_html($hash_ref, "inc_post");
        _output_template($hash_ref, $html) 
    }

    _output_markup($hash_ref)   if Config::get_value_for("write_markup");

    my $using_redis     = Config::get_value_for("write_html_to_redis");
    my $using_memcached = Config::get_value_for("write_html_to_memcached");

    my $html = _create_html($hash_ref, "post");

    if ( $using_redis ) {
        _write_html_to_redis($hash_ref, $html); 
        _write_homepage_to_redis($hash_ref) if $hash_ref->{post_type} ne "note";
    }

    if ( $using_memcached ) {
        _write_html_to_memcached($hash_ref, $html); 
        _write_homepage_to_memcached($hash_ref) if $hash_ref->{post_type} ne "note";
    }
}

sub _create_html {
    my $hash_ref  = shift;
    my $tmpl_file = shift;

    my $t = Page->new($tmpl_file);

    if ( $tmpl_file eq "post" ) {
        my $datetimestr = DateTimeFormatter::create_date_time_stamp_local("(monthname) (daynum), (yearfull) - (12hr):(0min) (a.p.) (TZ)");
        my $site_name = Config::get_value_for("site_name");
        $t->set_template_variable("home_page", Config::get_value_for("home_page")); 
        $t->set_template_variable("site_name", $site_name);
        $t->set_template_variable("pagetitle", "$hash_ref->{title} | $site_name");
        $t->set_template_variable("serverdatetime",    $datetimestr);
        $t->set_template_variable("css_dir_url",       Config::get_value_for("css_dir_url")); 
        $t->set_template_variable("textsize",          "medium");
        $t->set_template_variable("fonttype",          "sansserif");
        $t->set_template_variable("theme",             Config::get_value_for("cookie_prefix"));
    } 

    $t->set_template_variable("cgi_app",                 "");
    $t->set_template_variable("post_id",                 $hash_ref->{post_id});
    $t->set_template_variable("post_type",               $hash_ref->{post_type});
    $t->set_template_variable("parent_id",               $hash_ref->{parent_id});
    $t->set_template_variable("version",                 $hash_ref->{version});
    $t->set_template_variable("title",                   $hash_ref->{title}) if $hash_ref->{post_type} ne "note";
    $t->set_template_variable("uri_title",               $hash_ref->{uri_title});
#    $t->set_template_variable("formatted_text",          decode_entities($hash_ref->{formatted_text}, '<>&'));
    $t->set_template_variable("formatted_text",          $hash_ref->{formatted_text});
    $t->set_template_variable("author_name",             $hash_ref->{author_name});
    $t->set_template_variable("related_posts_count",     $hash_ref->{related_posts_count});
    $t->set_template_variable("created_date",            $hash_ref->{created_date});
    $t->set_template_variable("formatted_created_date",  $hash_ref->{formatted_created_date});
    $t->set_template_variable("reading_time",            $hash_ref->{reading_time});
    $t->set_template_variable("word_count",              $hash_ref->{word_count});

    if ( $hash_ref->{modified_date} ne $hash_ref->{created_date} ) {
        $t->set_template_variable("modified", 1);
        $t->set_template_variable("modified_date",           $hash_ref->{modified_date});
        $t->set_template_variable("formatted_modified_date", $hash_ref->{formatted_modified_date});
    }

    if ( $hash_ref->{table_of_contents} ) {
        my @toc_loop = _create_table_of_contents($hash_ref->{formatted_text});
        if ( @toc_loop ) {
            $t->set_template_variable("usingtoc", "1");
            $t->set_template_loop_data("toc_loop", \@toc_loop);
        }    
    } else {
        $t->set_template_variable("usingtoc", "0");
    }

    if ( $hash_ref->{usingimageheader} ) {
        $t->set_template_variable("usingimageheader", 1);
        $t->set_template_variable("imageheaderurl", $hash_ref->{imageheaderurl});
    }

    if ( $hash_ref->{usinglargeimageheader} ) {
        $t->set_template_variable("usinglargeimageheader", 1);
        $t->set_template_variable("largeimageheaderurl", $hash_ref->{largeimageheaderurl});
    }

    # write html of the post to the file system as an HTML::Template file.
    my $tmpl_output = $t->create_html($hash_ref->{title});

    return $tmpl_output;
}

sub _output_template {
    my $hash_ref    = shift;
    my $tmpl_output = shift;
    $tmpl_output = "<!-- tmpl_include name=\"header.tmpl\" -->\n" . $tmpl_output . "\n<!-- tmpl_include name=\"footer.tmpl\" -->\n";
    my $domain_name = Config::get_value_for("domain_name");
    my $filename = Config::get_value_for("post_templates") . "/" . $domain_name . "-" . $hash_ref->{post_id} . ".tmpl"; 
    if ( $filename =~  m/^([a-zA-Z0-9\/\.\-_]+)$/ ) {
        $filename = $1;
    } else {
        Error::report_error("500", "Bad file name.", "Could not write template for post id: $hash_ref->{post_id} filename: $filename");
    }
    open FILE, ">$filename" or Error::report_error("500", "Unable to open file for write.", "Post id: $hash_ref->{post_id} filename: $filename");
    print FILE $tmpl_output;
    close FILE;
}

sub _output_markup {
    my $hash_ref = shift;

    my $save_markup = $hash_ref->{markup_text} .  "\n\n<!-- author_name: $hash_ref->{author_name} -->\n<!-- created_date: $hash_ref->{created_date} -->\n<!-- modified_date: $hash_ref->{modified_date} -->\n";

    # write markup (multimarkdown or textile) to the file system.
    my $domain_name = Config::get_value_for("domain_name");
    my $markup_filename = Config::get_value_for("post_markup") . "/" . $domain_name . "-" . $hash_ref->{post_id} . ".markup"; 
    if ( $markup_filename =~  m/^([a-zA-Z0-9\/\.\-_]+)$/ ) {
        $markup_filename = $1;
    } else {
        Error::report_error("500", "Bad file name.", "Could not write markup for post id: $hash_ref->{post_id} filename: $markup_filename");
    }
    open FILE, ">$markup_filename" or Error::report_error("user", "Unable to open file for write.", "Post id: $hash_ref->{post_id} filename: $markup_filename");
    print FILE $save_markup;
    close FILE;
}

sub _write_html_to_redis {
    my $hash_ref = shift;
    my $html     = shift;

    my $hashname = Config::get_value_for("domain_name");
    my $key      = $hash_ref->{post_id}; 

    ## Defaults to $ENV{REDIS_SERVER} or 127.0.0.1:6379 per /etc/redis.conf
    my $redis = Redis->new; 
    $redis->hset( $hashname, $key => $html );
}

sub _write_homepage_to_redis {
    my $hash_ref = shift;

    my $hashname = Config::get_value_for("domain_name");
    my $key      = "homepage";
    
    my $html = get(Config::get_value_for("home_page") . "/articles");
    my $redis = Redis->new; 
    $redis->hset( $hashname, $key => $html );
}

sub _write_html_to_memcached {
    my $hash_ref = shift;
    my $html     = shift;

    $html .= "\n<!-- memcached -->\n";

    my $port        = Config::get_value_for("memcached_port");
    my $domain_name = Config::get_value_for("domain_name");
    my $key         = $domain_name . "-" . $hash_ref->{post_id}; 

    my $memd = Cache::Memcached::libmemcached->new( { 'servers' => [ "127.0.0.1:$port" ] } );
    my $rc = $memd->set($key, $html);
}

sub _write_homepage_to_memcached {
    my $hash_ref = shift;

#    my $html = get(Config::get_value_for("home_page") . "/articles");
    my $html = get(Config::get_value_for("home_page") . "/blocks");
    $html .= "\n<!-- memcached -->\n";
    
    my $port        = Config::get_value_for("memcached_port");
    my $domain_name = Config::get_value_for("domain_name");
    my $key         = $domain_name . "-homepage";

    my $memd = Cache::Memcached::libmemcached->new( { 'servers' => [ "127.0.0.1:$port" ] } );
    my $rc = $memd->set($key, $html);
}

sub _create_table_of_contents {
    my $str = shift;

    my @headers = ();
    my @loop_data = ();

    if ( @headers = $str =~ m{<!-- header:([1-6]):(.*?) -->}igs ) {
        my $len = @headers;
        for (my $i=0; $i<$len; $i+=2 ) {
            my %hash = ();
            $hash{level}      = $headers[$i];
            $hash{toclink}    = $headers[$i+1];
            $hash{cleantitle} = _clean_title($headers[$i+1]);
            push(@loop_data, \%hash); 
        }
    }

    return @loop_data;    
}

sub _clean_title {
    my $str = shift;
    $str =~ s|[-]||g;
    $str =~ s|[ ]|-|g;
    $str =~ s|[:]|-|g;
    $str =~ s|--|-|g;
    # only use alphanumeric, underscore, and dash in friendly link url
    $str =~ s|[^\w-]+||g;
    return $str;
}

1;
