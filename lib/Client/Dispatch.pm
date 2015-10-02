package Client::Dispatch;
use strict;
use warnings;
use Client::Modules;
use JRS::StrNumUtils;

my %cgi_params = Function::get_cgi_params_from_path_info("function", "one", "two", "three", "four");

my $dispatch_for = {
    showerror          =>   sub { return \&do_sub(       "Function",       "do_invalid_function"      ) },
    userarticles       =>   sub { return \&do_sub(       "ShowStream",     "show_articles_for_author" ) },
    articles           =>   sub { return \&do_sub(       "ShowStream",     "show_articles"            ) },
    blog               =>   sub { return \&do_sub(       "ShowStream",     "show_blog"                ) },
    loginform          =>   sub { return \&do_sub(       "LoginUser",      "show_login_form"          ) },
    login              =>   sub { return \&do_sub(       "LoginUser",      "login"                    ) },
    nopwdlogin         =>   sub { return \&do_sub(       "LoginUser",      "no_password_login"        ) },
    logout             =>   sub { return \&do_sub(       "LogoutUser",     "logout"                   ) },
    user               =>   sub { return \&do_sub(       "Profile",        "show_user"                ) },
    settings           =>   sub { return \&do_sub(       "Profile",        "show_user_settings_form"  ) },
    customizeuser      =>   sub { return \&do_sub(       "Profile",        "customize_user"           ) },
    changepassword     =>   sub { return \&do_sub(       "Profile",        "change_password"          ) },
    newpassword        =>   sub { return \&do_sub(       "Profile",        "create_new_password"      ) },
    newloginlink       =>   sub { return \&do_sub(       "Profile",        "create_new_login_link"    ) },
    signup             =>   sub { return \&do_sub(       "Signup",         "show_signup_form"         ) },
    createnewuser      =>   sub { return \&do_sub(       "Signup",         "create_new_user"          ) },
    activate           =>   sub { return \&do_sub(       "Signup",         "activate_account"         ) },
    post               =>   sub { return \&do_sub(       "ShowPost",       "show_post"                ) },
    source             =>   sub { return \&do_sub(       "ShowPost",       "show_post_source"         ) },
    relatedposts       =>   sub { return \&do_sub(       "Related",        "show_related_posts"       ) },
    versions           =>   sub { return \&do_sub(       "VersionList",    "show_versions"            ) },
    compare            =>   sub { return \&do_sub(       "VersionCompare", "compare_versions"         ) },
    tags               =>   sub { return \&do_sub(       "TagList",        "show_tags"                ) },
    tag                =>   sub { return \&do_sub(       "Search",         "tag_search"               ) },
    search             =>   sub { return \&do_sub(       "Search",         "string_search"            ) }, 
    searchform         =>   sub { return \&do_sub(       "Search",         "display_search_form"      ) }, 
    compose            =>   sub { return \&do_sub(       "Compose",        "show_new_post_form"       ) }, 
    createpost         =>   sub { return \&do_sub(       "NewPost",        "create_post"              ) }, 
    delete             =>   sub { return \&do_sub(       "ChangeStatus",   "delete_post"              ) }, 
    undelete           =>   sub { return \&do_sub(       "ChangeStatus",   "undelete_post"            ) }, 
    edit               =>   sub { return \&do_sub(       "EditPost",       "show_post_to_edit"        ) }, 
    updatepost         =>   sub { return \&do_sub(       "EditPost",       "update_post"              ) }, 
    splitscreen        =>   sub { return \&do_sub(       "Compose",        "show_splitscreen_form"    ) }, 
    splitscreenedit    =>   sub { return \&do_sub(       "EditPost",       "splitscreen_edit"         ) }, 
    notes              =>   sub { return \&do_sub(       "ShowStream",     "show_notes"               ) }, 
    drafts             =>   sub { return \&do_sub(       "ShowStream",     "show_drafts"              ) }, 
    changes            =>   sub { return \&do_sub(       "ShowStream",     "show_changes"             ) }, 
    blocks             =>   sub { return \&do_sub(       "ShowStream",     "show_blocks"              ) }, 
    textsize           =>   sub { return \&do_sub(       "TextSize",       "set_text_size"            ) },
    fonttype           =>   sub { return \&do_sub(       "FontType",       "set_font_type"            ) },
    #rss                =>   sub { return \&do_sub(            "RSS",       "get_rss"                  ) },
};

sub execute {
    my $function = $cgi_params{function};
#    $dispatch_for->{articles}->() if !defined($function) or !$function;
    $dispatch_for->{blocks}->() if !defined($function) or !$function;

# if using /post/ in the url, then use this line:
#    $dispatch_for->{showerror}->($function) unless exists $dispatch_for->{$function} ;

# if using post id number after the domain name, then use these lines:
    if ( StrNumUtils::is_numeric($cgi_params{function}) ) {
        $dispatch_for->{post}->($function); 
    }

    $dispatch_for->{showerror}->($function) unless exists $dispatch_for->{$function} ;

    defined $dispatch_for->{$function}->();
}

sub do_sub {
    my $module = shift;
    my $subroutine = shift;
    eval "require Client::$module" or Page->report_error("user", "Runtime Error (1):", $@);
    my %hash = %cgi_params;
    my $coderef = "$module\:\:$subroutine(\\%hash)"  or Page->report_error("user", "Runtime Error (2):", $@);
    eval "{ &$coderef };" or Page->report_error("user", "Runtime Error (2):", $@) ;
}

1;
